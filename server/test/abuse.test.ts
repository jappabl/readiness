import { afterEach, describe, expect, it, vi } from "vitest"
import {
  ABUSE_ALERT_MESSAGES,
  ABUSE_ALERT_PHOTOS,
  BURST_CAPACITY,
  REFILL_INTERVAL_SECONDS,
  tallyDaily,
  utcDay,
  type DailyUsage,
} from "../src/limits"
import { alertAbuse } from "../src/alarm"
import { RateBucket } from "../src/index"

// Pro is unlimited, and stays unlimited. This alarm exists so Hao hears about an install
// doing something no person does (a script, a shared key), and it must never be the
// thing that decides a request. Users see nothing.

const NOON = Date.UTC(2026, 8, 27, 12, 0, 0)
const NEXT_DAY = Date.UTC(2026, 8, 28, 0, 0, 1)

function fakeState(seed: Record<string, unknown> = {}) {
  const map = new Map<string, unknown>(Object.entries(seed))
  let queue: Promise<unknown> = Promise.resolve()
  return {
    storage: {
      get: async <T>(k: string) => map.get(k) as T | undefined,
      put: async (k: string, v: unknown) => void map.set(k, v),
    },
    blockConcurrencyWhile: <T>(fn: () => Promise<T>): Promise<T> => {
      const run = queue.then(fn)
      queue = run.catch(() => undefined)
      return run as Promise<T>
    },
  } as unknown as DurableObjectState
}

/** Runs `count` requests through the pure tally and returns every alert it raised. */
function run(count: number, kind: "message" | "photo", start?: DailyUsage, now = NOON) {
  let usage = start
  const alerts: DailyUsage[] = []
  for (let i = 0; i < count; i++) {
    const out = tallyDaily(usage, kind, now)
    usage = out.usage
    if (out.alert) alerts.push(out.usage)
  }
  return { usage: usage!, alerts }
}

describe("the daily tally", () => {
  it("names the day in UTC", () => {
    expect(utcDay(NOON)).toBe("2026-09-27")
    expect(utcDay(Date.UTC(2026, 8, 27, 23, 59, 59))).toBe("2026-09-27")
    expect(utcDay(NEXT_DAY)).toBe("2026-09-28")
  })

  it("counts coach messages and meal photos separately", () => {
    let usage = tallyDaily(undefined, "message", NOON).usage
    usage = tallyDaily(usage, "message", NOON).usage
    usage = tallyDaily(usage, "photo", NOON).usage
    expect(usage).toMatchObject({ day: "2026-09-27", messages: 2, photos: 1 })
  })

  it("stays silent below the message line and fires on crossing it", () => {
    const below = run(ABUSE_ALERT_MESSAGES - 1, "message")
    expect(below.alerts).toHaveLength(0)
    const crossing = tallyDaily(below.usage, "message", NOON)
    expect(crossing.alert).toBe(true)
    expect(crossing.usage.messages).toBe(ABUSE_ALERT_MESSAGES)
  })

  it("fires on crossing the photo line", () => {
    const { alerts } = run(ABUSE_ALERT_PHOTOS, "photo")
    expect(alerts).toHaveLength(1)
    expect(alerts[0]!.photos).toBe(ABUSE_ALERT_PHOTOS)
  })

  it("fires exactly once per day, however far past the line it goes", () => {
    const { alerts } = run(ABUSE_ALERT_MESSAGES * 3, "message")
    expect(alerts).toHaveLength(1)
  })

  it("fires once per day even when both lines are crossed", () => {
    const messages = run(ABUSE_ALERT_MESSAGES, "message")
    expect(messages.alerts).toHaveLength(1)
    const photos = run(ABUSE_ALERT_PHOTOS * 2, "photo", messages.usage)
    expect(photos.alerts).toHaveLength(0)
  })

  it("starts again on a new UTC day, and can fire again", () => {
    const today = run(ABUSE_ALERT_MESSAGES, "message")
    expect(today.alerts).toHaveLength(1)
    const fresh = tallyDaily(today.usage, "message", NEXT_DAY)
    expect(fresh.usage).toEqual({ day: "2026-09-28", messages: 1, photos: 0, alerted: false })
    expect(fresh.alert).toBe(false)
    const tomorrow = run(ABUSE_ALERT_MESSAGES - 1, "message", fresh.usage, NEXT_DAY)
    expect(tomorrow.alerts).toHaveLength(1)
  })

  it("the lines are the ones Hao chose", () => {
    expect(ABUSE_ALERT_MESSAGES).toBe(1000)
    expect(ABUSE_ALERT_PHOTOS).toBe(200)
  })
})

describe("the alarm inside the meter", () => {
  afterEach(() => vi.useRealTimers())

  const consume = async (bucket: RateBucket, isSubscriber: boolean, kind: "message" | "photo" = "message") =>
    (await bucket.fetch(
      new Request("https://bucket/consume", { method: "POST", body: JSON.stringify({ isSubscriber, kind }) }),
    )).json<{ allowed: boolean; status: number | null; retryAfter: number | null; alert: DailyUsage | null }>()

  const nearTheLine = (): DailyUsage => ({
    day: "2026-09-27",
    messages: ABUSE_ALERT_MESSAGES - 1,
    photos: 0,
    alerted: false,
  })

  it("reports the crossing once, for a subscriber, and still allows the request", async () => {
    vi.useFakeTimers()
    vi.setSystemTime(NOON)
    const bucket = new RateBucket(fakeState({ daily: nearTheLine() }))
    const first = await consume(bucket, true)
    expect(first).toMatchObject({ allowed: true, status: null })
    expect(first.alert).toMatchObject({ day: "2026-09-27", messages: ABUSE_ALERT_MESSAGES, photos: 0 })
    vi.setSystemTime(NOON + REFILL_INTERVAL_SECONDS * 1000)
    const second = await consume(bucket, true)
    expect(second).toMatchObject({ allowed: true, alert: null })
  })

  it("never changes the decision, whatever the count says", async () => {
    vi.useFakeTimers()
    vi.setSystemTime(NOON)
    const wayOver: DailyUsage = { day: "2026-09-27", messages: 50_000, photos: 9_000, alerted: true }
    for (const isSubscriber of [true, false]) {
      for (const kind of ["message", "photo"] as const) {
        const plain = new RateBucket(fakeState())
        const flagged = new RateBucket(fakeState({ daily: { ...wayOver } }))
        const crossing = new RateBucket(fakeState({ daily: nearTheLine() }))
        // Past the burst too, so the 429 and the 402 are both compared, not only the yes.
        for (let i = 0; i < BURST_CAPACITY + 2; i++) {
          const a = await consume(plain, isSubscriber, kind)
          const b = await consume(flagged, isSubscriber, kind)
          const c = await consume(crossing, isSubscriber, kind)
          const decision = ({ allowed, status, retryAfter }: typeof a) => ({ allowed, status, retryAfter })
          expect(decision(b), `${isSubscriber} ${kind} ${i}`).toEqual(decision(a))
          expect(decision(c), `${isSubscriber} ${kind} ${i}`).toEqual(decision(a))
        }
      }
    }
  })

  it("does not count free traffic, which the free tier already caps", async () => {
    vi.useFakeTimers()
    vi.setSystemTime(NOON)
    const bucket = new RateBucket(fakeState({ daily: nearTheLine() }))
    const out = await consume(bucket, false)
    expect(out.alert).toBeNull()
  })

  it("does not count a request the burst limit refused", async () => {
    vi.useFakeTimers()
    vi.setSystemTime(NOON)
    const empty = { tokens: 0, updated: NOON }
    const bucket = new RateBucket(fakeState({ bucket: empty, daily: nearTheLine() }))
    const out = await consume(bucket, true)
    expect(out).toMatchObject({ allowed: false, status: 429, alert: null })
  })
})

describe("raising the alarm", () => {
  afterEach(() => vi.restoreAllMocks())

  const usage: DailyUsage = { day: "2026-09-27", messages: 1000, photos: 12, alerted: true }
  const INSTALL = "AbCdEf0123456789rawAttestedKeyIdThatMustNeverBeLogged=="

  it("always writes one structured warning, with the install hashed and never raw", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    await alertAbuse(INSTALL, usage, {})
    expect(warn).toHaveBeenCalledTimes(1)
    const line = String(warn.mock.calls[0]![0])
    expect(line).not.toContain(INSTALL)
    expect(line).not.toContain(INSTALL.slice(0, 8))
    const parsed = JSON.parse(line)
    expect(parsed).toMatchObject({ event: "abuse_alert", day: "2026-09-27", messages: 1000, photos: 12 })
    expect(parsed.install).toMatch(/^[0-9a-f]{12}$/)
  })

  it("hashes the same install to the same id, so two days can be matched up", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    await alertAbuse(INSTALL, usage, {})
    await alertAbuse(INSTALL, { ...usage, day: "2026-09-28" }, {})
    await alertAbuse("someone-else", usage, {})
    const ids = warn.mock.calls.map((call) => JSON.parse(String(call[0])).install)
    expect(ids[0]).toBe(ids[1])
    expect(ids[2]).not.toBe(ids[0])
  })

  it("works with no webhook configured, and fetches nothing", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {})
    const fetcher = vi.fn()
    await expect(alertAbuse(INSTALL, usage, {}, fetcher)).resolves.toBeUndefined()
    await expect(alertAbuse(INSTALL, usage, { ALERT_WEBHOOK_URL: "" }, fetcher)).resolves.toBeUndefined()
    expect(fetcher).not.toHaveBeenCalled()
  })

  it("posts one plain text message that ntfy, Discord and Slack can all read", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {})
    const fetcher = vi.fn(async () => new Response("ok"))
    await alertAbuse(INSTALL, usage, { ALERT_WEBHOOK_URL: "https://hooks.example/abc" }, fetcher)
    expect(fetcher).toHaveBeenCalledTimes(1)
    const [url, init] = fetcher.mock.calls[0] as unknown as [string, RequestInit]
    expect(url).toBe("https://hooks.example/abc")
    expect(init.method).toBe("POST")
    expect(new Headers(init.headers).get("content-type")).toBe("application/json")
    const body = JSON.parse(String(init.body))
    // Slack reads `text`, Discord reads `content`; ntfy is pointed at `text` by a template.
    expect(typeof body.text).toBe("string")
    expect(body.content).toBe(body.text)
    expect(body.text).toContain("1000")
    expect(body.text).not.toContain(INSTALL)
  })

  it("swallows a webhook that throws", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {})
    const fetcher = vi.fn(async () => { throw new Error("network down") })
    await expect(
      alertAbuse(INSTALL, usage, { ALERT_WEBHOOK_URL: "https://hooks.example/abc" }, fetcher),
    ).resolves.toBeUndefined()
  })

  it("swallows a webhook that answers with an error", async () => {
    vi.spyOn(console, "warn").mockImplementation(() => {})
    const fetcher = vi.fn(async () => new Response("nope", { status: 500 }))
    await expect(
      alertAbuse(INSTALL, usage, { ALERT_WEBHOOK_URL: "https://hooks.example/abc" }, fetcher),
    ).resolves.toBeUndefined()
  })

  it("never puts the webhook address in the logs", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {})
    const secret = "https://hooks.example/very-secret-token"
    await alertAbuse(INSTALL, usage, { ALERT_WEBHOOK_URL: secret }, vi.fn(async () => { throw new Error(secret) }))
    for (const call of warn.mock.calls) expect(call.map(String).join(" ")).not.toContain("very-secret-token")
  })
})
