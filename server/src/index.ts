/**
 * The proxy.
 *
 * Holds the provider keys, decides whether the caller is entitled, meters them, composes
 * the request, and forwards. The client never sends a provider body and never sees a
 * provider key.
 */
import { allowance, consume, freshBucket, type BucketState } from "./limits"
import { entitlement } from "./entitlement"
import { coachBody, mealBody, trim } from "./prompt"
import { InvalidRequest, parseCoachBody, parseMealBody, MAX_MESSAGES } from "./schema"

export interface Env {
  ANTHROPIC_API_KEY: string
  DEEPSEEK_API_KEY: string
  DEV_SHARED_SECRET?: string
  COACH_PROVIDER: string
  COACH_MODEL: string
  MEAL_PROVIDER: string
  MEAL_MODEL: string
  REQUIRE_ATTESTATION: string
  APPLE_TEAM_ID: string
  BUNDLE_ID: string
  BUCKET: DurableObjectNamespace
  USAGE: KVNamespace
}

const PROVIDERS: Record<string, { url: string; key: (env: Env) => string }> = {
  anthropic: { url: "https://api.anthropic.com/v1/messages", key: (e) => e.ANTHROPIC_API_KEY },
  deepseek: { url: "https://api.deepseek.com/anthropic/v1/messages", key: (e) => e.DEEPSEEK_API_KEY },
}

/**
 * The token bucket, in a Durable Object because it has to be right under concurrency.
 * Two requests racing against KV would each read the same count and both be allowed.
 */
export class RateBucket implements DurableObject {
  constructor(private state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const stored = (await this.state.storage.get<BucketState>("bucket")) ?? freshBucket()
    const decision = consume(stored, Date.now())
    await this.state.storage.put("bucket", decision.state)
    return Response.json({ allowed: decision.allowed, retryAfter: decision.retryAfter })
  }
}

function problem(status: number, detail: string, extra?: Record<string, string>): Response {
  return new Response(JSON.stringify({ error: detail }), {
    status,
    headers: { "content-type": "application/json", ...(extra ?? {}) },
  })
}

/**
 * Who is calling.
 *
 * App Attest is the layer that stops someone pointing curl at this. It stays off until
 * the project has a real DEVELOPMENT_TEAM, because the attestation payload is validated
 * against <teamID>.<bundleID> and there is nothing to validate against yet. While it is
 * off, a shared development secret is required instead, so the endpoint is never simply
 * open.
 */
async function identify(request: Request, env: Env): Promise<{ id: string } | Response> {
  const attestation = request.headers.get("x-jett-attestation")
  const requireAttestation = env.REQUIRE_ATTESTATION === "true"

  if (requireAttestation) {
    if (!attestation) return problem(401, "attestation required")
    // Deliberately unimplemented rather than faked: see docs/briefs/model-proxy.md.
    // Returning a permissive default here would make the only anti-abuse control a
    // comment.
    return problem(501, "App Attest verification is not implemented yet")
  }

  const dev = request.headers.get("x-jett-dev-secret")
  if (!env.DEV_SHARED_SECRET || dev !== env.DEV_SHARED_SECRET) {
    return problem(401, "not authorised")
  }
  const install = request.headers.get("x-jett-install")
  if (!install || install.length < 8 || install.length > 128) {
    return problem(401, "missing install id")
  }
  return { id: install }
}

async function meter(id: string, isSubscriber: boolean, env: Env): Promise<Response | null> {
  // Burst first: it applies to everyone, including subscribers, because unlimited means
  // no monthly cap rather than no rate limit.
  const bucket = env.BUCKET.get(env.BUCKET.idFromName(id))
  const decision = (await (await bucket.fetch("https://bucket/consume")).json()) as {
    allowed: boolean
    retryAfter: number | null
  }
  if (!decision.allowed) {
    return problem(429, "one at a time", { "retry-after": String(decision.retryAfter ?? 12) })
  }

  if (isSubscriber) return null

  const used = Number((await env.USAGE.get(`free:${id}`)) ?? "0")
  const room = allowance(used, false)
  if (!room.allowed) return problem(402, "free messages used up")
  await env.USAGE.put(`free:${id}`, String(used + 1))
  return null
}

async function callProvider(
  providerName: string,
  body: Record<string, unknown>,
  env: Env,
): Promise<Response> {
  const provider = PROVIDERS[providerName]
  if (!provider) return problem(500, `unknown provider ${providerName}`)

  const upstream = await fetch(provider.url, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": provider.key(env),
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify(body),
  })

  if (!upstream.ok) {
    const detail = await upstream.text()
    // 5xx from a provider is a 503 to the client: it is not their request that is wrong.
    const status = upstream.status >= 500 ? 503 : upstream.status
    return problem(status, detail.slice(0, 500))
  }
  return upstream
}

async function handleCoach(request: Request, env: Env, id: string): Promise<Response> {
  const parsed = parseCoachBody(await request.json())
  const result = await entitlement(
    request.headers.get("x-jett-transaction") ?? undefined,
    env.BUNDLE_ID,
    Date.now(),
    env.REQUIRE_ATTESTATION !== "true", // dev mode trusts the claim it cannot yet verify
  )
  const limited = await meter(id, result.subscriber, env)
  if (limited) return limited

  const body = coachBody({
    model: env.COACH_MODEL,
    context: parsed.context,
    unitsAreMetric: parsed.unitsAreMetric,
    messages: trim(parsed.messages, MAX_MESSAGES),
    offersTools: parsed.offersTools,
  })

  const upstream = await callProvider(env.COACH_PROVIDER, body, env)
  return streamOrPassError(upstream, result.subscriber)
}

/**
 * Wrap a successful provider stream, and pass anything else through untouched.
 *
 * The first version checked only for a missing body. Every error this file produces has
 * a body, so a provider authentication failure was being rewrapped as 200 OK with an
 * event-stream content type and the error JSON inside it. The client would have parsed
 * that as an empty answer and never run its error path. Caught by pointing the local
 * worker at the real API with a deliberately wrong key.
 */
export function streamOrPassError(upstream: Response, subscriber: boolean): Response {
  if (!upstream.ok || !upstream.body) return upstream
  // Straight through, unbuffered. A proxy that accumulates the body destroys the one
  // thing the coach is judged on, which is how quickly the first words appear.
  return new Response(upstream.body, {
    status: 200,
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-store",
      "x-jett-subscriber": String(subscriber),
    },
  })
}

async function handleMeal(request: Request, env: Env, id: string): Promise<Response> {
  const parsed = parseMealBody(await request.json())
  const limited = await meter(id, true, env) // photos are not on the free-message meter
  if (limited) return limited

  const upstream = await callProvider(
    env.MEAL_PROVIDER,
    mealBody({
      model: env.MEAL_MODEL,
      imageBase64: parsed.imageBase64,
      mediaType: parsed.mediaType,
      note: parsed.note,
    }),
    env,
  )
  if (!upstream.ok) return upstream
  return new Response(await upstream.text(), {
    status: 200,
    headers: { "content-type": "application/json" },
  })
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url)
    if (request.method !== "POST") return problem(405, "use POST")

    const who = await identify(request, env)
    if (who instanceof Response) return who

    try {
      switch (url.pathname) {
        case "/v1/coach":
          return await handleCoach(request, env, who.id)
        case "/v1/meal":
          return await handleMeal(request, env, who.id)
        default:
          return problem(404, "no such endpoint")
      }
    } catch (error) {
      if (error instanceof InvalidRequest) return problem(400, error.message)
      return problem(500, "unhandled")
    }
  },
} satisfies ExportedHandler<Env>
