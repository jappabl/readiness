/**
 * The proxy.
 *
 * Holds the provider keys, decides whether the caller is entitled, meters them, composes
 * the request, and forwards. The client never sends a provider body and never sees a
 * provider key.
 */
import { freshBucket, meterDecision, type MeterState } from "./limits"
import { entitlement, type Trust } from "./entitlement"
import { APPLE_ROOT_G3 } from "./apple-root"
import { coachBody, mealBody, trim } from "./prompt"
import { InvalidRequest, parseCoachBody, parseMealBody, MAX_MESSAGES } from "./schema"
import { legalPage } from "./legal"
import { base64ToBytes, verifyAssertion, verifyAttestation, type AttestedKey } from "./attest"

export interface Env {
  ANTHROPIC_API_KEY: string
  DEEPSEEK_API_KEY: string
  /// Signs the anti-replay challenge. A secret, set with `wrangler secret put`, never
  /// a value from `wrangler.toml`: everything in that file ships in the open, and a
  /// challenge anybody can mint is not a challenge.
  CHALLENGE_SECRET?: string
  COACH_PROVIDER: string
  COACH_MODEL: string
  MEAL_PROVIDER: string
  MEAL_MODEL: string
  REQUIRE_ATTESTATION: string
  ROLL: DurableObjectNamespace
  /// Installs that skip the free-message cap: a comma-separated list of attested key
  /// ids, or "*" for every caller. Empty in production. A testing lever, not a
  /// purchase, so it never touches entitlement.
  UNLIMITED_IDS?: string
  APPLE_TEAM_ID: string
  BUNDLE_ID: string
  /// The app's numeric Apple ID from App Store Connect, needed to verify production
  /// purchases. Empty until the app record exists; production purchases fail closed
  /// until then, and sandbox ones, which is all TestFlight makes, do not need it.
  APP_APPLE_ID?: string
  BUCKET: DurableObjectNamespace
  /// One object per attested key, holding its public key and its counter.
  ATTEST: DurableObjectNamespace
}

/**
 * What an install is, once it has proved itself.
 *
 * A Durable Object rather than KV because the counter is the replay defence and has to
 * be right under concurrency: two requests racing against an eventually consistent store
 * would both read the same counter and both be accepted, which is precisely the replay
 * the counter exists to stop.
 */
/**
 * The member roll. One object for the whole service, holding one number.
 *
 * Every install is given the next one the first time it registers, and the first
 * hundred are founders. A promise with a number in it has to be countable by something,
 * and a counter that two simultaneous registrations can both read is a promise that
 * hands out member fourteen twice.
 */
export class MemberRoll implements DurableObject {
  constructor(private state: DurableObjectState) {}

  async fetch(): Promise<Response> {
    return await this.state.blockConcurrencyWhile(async () => {
      const issued = (await this.state.storage.get<number>("issued")) ?? 0
      const member = issued + 1
      await this.state.storage.put("issued", member)
      return Response.json({ member })
    })
  }
}

export class AttestedInstall implements DurableObject {
  constructor(private state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const body = (await request.json()) as
      | { op: "register"; key: AttestedKey; member: number }
      | { op: "load" }
      | { op: "advance"; counter: number }

    return await this.state.blockConcurrencyWhile(async () => {
      const stored = await this.state.storage.get<AttestedKey>("key")
      const member = await this.state.storage.get<number>("member")
      switch (body.op) {
        case "register":
          // Registering twice is not an error, but it must not reset a counter: that
          // would hand a replayed assertion a clean slate. The member number is the
          // same bargain for a different reason: re-registering must not spend a
          // second place from the roll, or a hundred founders becomes however many
          // times the first hundred people reinstalled.
          if (!stored) await this.state.storage.put("key", body.key)
          if (member === undefined) await this.state.storage.put("member", body.member)
          return Response.json({ ok: true, member: member ?? body.member })
        case "load":
          return Response.json({ key: stored ?? null, member: member ?? null })
        case "advance":
          if (!stored) return Response.json({ ok: false })
          await this.state.storage.put("key", { ...stored, counter: body.counter })
          return Response.json({ ok: true })
      }
    })
  }
}

/**
 * A challenge, so an attestation or an assertion cannot be replayed.
 *
 * Signed rather than stored: the Worker has no session to keep it in, and a challenge
 * that carries its own expiry and its own signature needs no round trip to validate.
 */
export async function issueChallenge(env: Env): Promise<string> {
  const secret = env.CHALLENGE_SECRET
  // Fail closed. This used to fall back to the bundle id, which is printed in the
  // app's own Info.plist and sits in the App Store URL, so every challenge could be
  // minted by anybody who knew the name of the app. A fallback key is worse than no
  // key: the door still opens, and from outside it looks locked.
  if (!secret) throw new Error("no challenge secret")
  const payload = `${Date.now()}.${crypto.randomUUID()}`
  return `${payload}.${await hmac(payload, secret)}`
}

const CHALLENGE_LIFETIME_MS = 5 * 60 * 1000

export async function challengeIsValid(challenge: string, env: Env, now: number): Promise<boolean> {
  const secret = env.CHALLENGE_SECRET
  if (!secret) return false
  const parts = challenge.split(".")
  if (parts.length !== 3) return false
  const [issued, nonce, signature] = parts as [string, string, string]
  const expected = await hmac(`${issued}.${nonce}`, secret)
  // Compared the slow way on purpose: `!==` returns at the first differing byte, and
  // the number of bytes it got through is a measurement of how close a guess was.
  if (!(await secretsMatch(signature, expected))) return false
  const age = now - Number(issued)
  return Number.isFinite(age) && age >= 0 && age < CHALLENGE_LIFETIME_MS
}

async function hmac(message: string, secret: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  )
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message))
  return [...new Uint8Array(signature)].map((b) => b.toString(16).padStart(2, "0")).join("")
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
    const { isSubscriber } = (await request.json()) as { isSubscriber: boolean }
    // Both meters read and written inside one blocked section. The free counter used to
    // live in KV as a get followed by a put, which two concurrent requests could both
    // pass before either wrote.
    return await this.state.blockConcurrencyWhile(async () => {
      const stored: MeterState = {
        bucket: (await this.state.storage.get<MeterState["bucket"]>("bucket")) ?? freshBucket(),
        freeUsed: (await this.state.storage.get<number>("freeUsed")) ?? 0,
      }
      const outcome = meterDecision(stored, isSubscriber, Date.now())
      await this.state.storage.put("bucket", outcome.state.bucket)
      await this.state.storage.put("freeUsed", outcome.state.freeUsed)
      return Response.json({
        allowed: outcome.allowed,
        status: outcome.status ?? null,
        retryAfter: outcome.retryAfter ?? null,
      })
    })
  }
}

function problem(status: number, detail: string, extra?: Record<string, string>): Response {
  return new Response(JSON.stringify({ error: detail }), {
    status,
    headers: { "content-type": "application/json", ...(extra ?? {}) },
  })
}

type AttestOutcome = { ok: true; id: string } | { ok: false; reason: string }

/**
 * Whether this request carries a valid assertion from a registered install.
 *
 * Lifted out of `identify` so that the pre-flight check and the real gate run the same
 * code. A dry run that verifies something slightly different is worse than no dry run:
 * it produces confidence and no safety.
 */
async function verifyAttested(request: Request, env: Env): Promise<AttestOutcome> {
  const attestation = request.headers.get("x-jett-attestation")
  const keyID = request.headers.get("x-jett-key-id")
  const challenge = request.headers.get("x-jett-challenge")
  if (!attestation || !keyID || !challenge) {
    return { ok: false, reason: "the request carried no attestation headers" }
  }
  if (!(await challengeIsValid(challenge, env, Date.now()))) {
    return { ok: false, reason: "the challenge was not one we issued in the last five minutes" }
  }

  const install = env.ATTEST.get(env.ATTEST.idFromName(keyID))
  const stored = (await (
    await install.fetch("https://attest/load", {
      method: "POST",
      body: JSON.stringify({ op: "load" }),
    })
  ).json()) as { key: AttestedKey | null }
  if (!stored.key) return { ok: false, reason: "this key has never completed registration" }

  try {
    // The body is signed along with the challenge, so an assertion captured from one
    // request cannot be replayed against a different question.
    const body = new Uint8Array(await request.clone().arrayBuffer())
    const signed = new Uint8Array(new TextEncoder().encode(challenge).length + body.length)
    signed.set(new TextEncoder().encode(challenge))
    signed.set(body, new TextEncoder().encode(challenge).length)
    const counter = await verifyAssertion({
      assertion: base64ToBytes(attestation),
      signedData: signed,
      key: stored.key,
      appID: `${env.APPLE_TEAM_ID}.${env.BUNDLE_ID}`,
    })
    await install.fetch("https://attest/advance", {
      method: "POST",
      body: JSON.stringify({ op: "advance", counter }),
    })
    return { ok: true, id: keyID }
  } catch (error) {
    return { ok: false, reason: `the assertion did not verify: ${String(error)}` }
  }
}

/**
 * Who is calling.
 *
 * App Attest, and nothing else. There used to be a second way in behind a shared
 * development secret, for the stretch before attestation was verified. It has not been
 * reachable since `REQUIRE_ATTESTATION` went to "true", and unreachable authentication
 * code is the kind that rots without anybody noticing, so it is gone.
 *
 * `REQUIRE_ATTESTATION` still exists and still means something, but something narrower:
 * it gates the `/v1/attest/check` diagnostic. Turning it off no longer opens this door,
 * it only lets a device ask why its proof was refused.
 *
 * What this costs: the Simulator cannot reach the coach at all. App Attest does not
 * exist there, so it never could.
 */
async function identify(request: Request, env: Env): Promise<{ id: string } | Response> {
  const outcome = await verifyAttested(request, env)
  // Never say which check failed. The difference between "unknown key" and "bad
  // signature" is an oracle for somebody probing it. `/v1/attest/check` says, and only
  // while attestation is not yet the only way in.
  if (!outcome.ok) return problem(401, "not authorised")
  // The attested key id, which the client cannot choose.
  return { id: outcome.id }
}

/**
 * Compare a secret without leaking its length or prefix through timing. Digest both
 * sides first so the comparison is fixed-length whatever arrives, then accumulate the
 * difference over every byte rather than returning early.
 */
async function secretsMatch(candidate: string | null, expected: string): Promise<boolean> {
  if (candidate === null) return false
  const encoder = new TextEncoder()
  const [a, b] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(candidate)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ])
  const left = new Uint8Array(a)
  const right = new Uint8Array(b)
  let difference = 0
  for (let i = 0; i < left.length; i++) difference |= (left[i] ?? 0) ^ (right[i] ?? 0)
  return difference === 0
}

/**
 * Whether this install is on the testing allowlist.
 *
 * Deliberately separate from entitlement. A subscriber is somebody the App Store says
 * paid, and marking a tester as one would put a lie in the place that has to stay
 * honest. This lifts the free-message cap and nothing else.
 */
function isUnlimited(id: string, env: Env): boolean {
  const list = (env.UNLIMITED_IDS ?? "").trim()
  if (!list) return false
  if (list === "*") return true
  return list
    .split(",")
    .map((entry) => entry.trim())
    .includes(id)
}

async function meter(id: string, isSubscriber: boolean, env: Env): Promise<Response | null> {
  const bucket = env.BUCKET.get(env.BUCKET.idFromName(id))
  const decision = (await (
    await bucket.fetch("https://bucket/consume", {
      method: "POST",
      body: JSON.stringify({ isSubscriber }),
    })
  ).json()) as { allowed: boolean; status: number | null; retryAfter: number | null }

  if (decision.allowed) return null
  if (decision.status === 429) {
    return problem(429, "one at a time", { "retry-after": String(decision.retryAfter ?? 12) })
  }
  return problem(402, "free messages used up")
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

/**
 * Registering an install, once.
 *
 * Open by design: there is nothing to authenticate with yet, which is the whole point of
 * the step. What stops it being abused is that the attestation has to come from Apple,
 * be built around a challenge we issued in the last five minutes, and name this app.
 */
async function handleAttest(request: Request, env: Env): Promise<Response> {
  const body = (await request.json()) as {
    keyId?: string
    challenge?: string
    attestation?: string
  }
  if (!body.keyId || !body.challenge || !body.attestation) {
    return problem(400, "keyId, challenge and attestation are required")
  }
  if (!(await challengeIsValid(body.challenge, env, Date.now()))) {
    return problem(401, "stale challenge")
  }

  try {
    const key = await verifyAttestation({
      attestation: base64ToBytes(body.attestation),
      challenge: body.challenge,
      keyID: body.keyId,
      appID: `${env.APPLE_TEAM_ID}.${env.BUNDLE_ID}`,
    })
    const install = env.ATTEST.get(env.ATTEST.idFromName(body.keyId))
    // Claimed before the install is asked, because the install is the only thing that
    // can tell us whether it already holds one, and a number claimed for an install
    // that turns out to have one is simply not stored. A gap in the roll costs nothing;
    // handing the same number to two people costs the only thing the roll is for.
    const claimed = await (
      await env.ROLL.get(env.ROLL.idFromName("roll")).fetch("https://roll/claim")
    ).json<{ member: number }>()
    const registered = await (
      await install.fetch("https://attest/register", {
        method: "POST",
        body: JSON.stringify({ op: "register", key, member: claimed.member }),
      })
    ).json<{ member: number }>()
    return Response.json({ ok: true, member: registered.member })
  } catch (error) {
    // Same bargain as `/v1/attest/check`: the reason a registration was refused is an
    // oracle, and it is also the only way to find out why a real device is being turned
    // away. It is said while attestation is not yet the gate, and not after.
    if (env.REQUIRE_ATTESTATION !== "true") {
      return problem(401, `not authorised: ${String(error)}`)
    }
    return problem(401, "not authorised")
  }
}

/** Apple's root and nothing else. The only place anything is trusted to sign a purchase. */
function trustFor(env: Env): Trust {
  const appAppleId = Number(env.APP_APPLE_ID)
  return {
    bundleId: env.BUNDLE_ID,
    roots: [APPLE_ROOT_G3],
    appAppleId: Number.isInteger(appAppleId) && appAppleId > 0 ? appAppleId : undefined,
  }
}

async function handleCoach(request: Request, env: Env, id: string): Promise<Response> {
  const parsed = parseCoachBody(await request.json())
  const result = await entitlement(
    request.headers.get("x-jett-transaction") ?? undefined,
    trustFor(env),
    Date.now(),
  )
  const limited = await meter(id, result.subscriber || isUnlimited(id, env), env)
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

    // Before the method check and before identification: these are pages a reviewer,
    // and anybody else, has to be able to open without holding a key.
    if (request.method === "GET") {
      const legal = legalPage(url.pathname)
      if (legal) return legal
    }

    if (request.method !== "POST") return problem(405, "use POST")

    // Both before identification, because they are how an install becomes identifiable.
    if (url.pathname === "/v1/challenge") {
      if (!env.CHALLENGE_SECRET) return problem(503, "not configured")
      return Response.json({ challenge: await issueChallenge(env) })
    }
    if (url.pathname === "/v1/attest") return await handleAttest(request, env)
    // A dry run of the gate, for the one job of finding out whether attestation works
    // on a real device *before* it becomes the only way in. Flipping the flag blind
    // means the failure mode is an app that cannot reach its own backend.
    //
    // It names the reason a proof failed, which is an oracle, so it answers only while
    // attestation is not yet required: the moment it would be worth probing, it is gone.
    if (url.pathname === "/v1/attest/check") {
      if (env.REQUIRE_ATTESTATION === "true") return problem(404, "no such endpoint")
      const outcome = await verifyAttested(request, env)
      return Response.json(outcome)
    }

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
