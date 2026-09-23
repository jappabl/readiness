import { describe, expect, it } from "vitest"
import { entitlement } from "../src/entitlement"
import { handleAppleNotification, type Env } from "../src/index"
import { applyRefund, RefundLedger, refundEvent, verifiedNotification } from "../src/refunds"
import { APPLE_ROOT_G3 } from "../src/apple-root"
import { BUNDLE, forged, notification, purchase, signed, TEST_ROOT } from "./storekit"

const trustingTests = { bundleId: BUNDLE, roots: [TEST_ROOT] }
const trustingApple = { bundleId: BUNDLE, roots: [APPLE_ROOT_G3] }
const REFUNDED = "2000000000000001"

function fakeState() {
  const map = new Map<string, unknown>()
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

/** One ledger per transaction, the way the namespace hands them out. */
function fakeEnv() {
  const ledgers = new Map<string, RefundLedger>()
  const REFUNDS = {
    idFromName: (name: string) => name,
    get: (id: string) => {
      if (!ledgers.has(id)) ledgers.set(id, new RefundLedger(fakeState()))
      const ledger = ledgers.get(id)!
      return { fetch: (url: string, init?: RequestInit) => ledger.fetch(new Request(url, init)) }
    },
  }
  return { env: { BUNDLE_ID: BUNDLE, REFUNDS } as unknown as Env, ledgers }
}

async function isRevoked(env: Env, transactionId: string) {
  const stub = env.REFUNDS.get(env.REFUNDS.idFromName(transactionId))
  return (await (await stub.fetch("https://refunds/status", { method: "POST", body: "{}" })).json<{ revoked: boolean }>()).revoked
}

const post = (body: unknown) =>
  new Request("https://proxy/v1/apple/notifications", { method: "POST", body: JSON.stringify(body) })

describe("which of Apple's notifications change anything", () => {
  it("a refund and a family member losing access both end it", () => {
    expect(refundEvent("REFUND")).toBe("revoke")
    expect(refundEvent("REVOKE")).toBe("revoke")
  })
  it("a reversed refund gives it back", () => {
    expect(refundEvent("REFUND_REVERSED")).toBe("restore")
  })
  it("everything else is acknowledged and ignored", () => {
    for (const type of ["SUBSCRIBED", "DID_RENEW", "REFUND_DECLINED", "CONSUMPTION_REQUEST", "EXPIRED", "TEST"]) {
      expect(refundEvent(type), type).toBeNull()
    }
  })
})

// Apple retries for days and makes no promise about order, so a refund can arrive after
// the reversal that cancelled it. Whatever Apple signed last is what stands.
describe("the ledger keeps Apple's latest word", () => {
  it("a refund and then its reversal leaves it working", () => {
    expect(applyRefund(applyRefund(undefined, "revoke", 1), "restore", 2)).toEqual({ revoked: false, at: 2 })
  })
  it("a late copy of the original refund does not undo the reversal", () => {
    const reversed = applyRefund(applyRefund(undefined, "revoke", 1), "restore", 2)
    expect(applyRefund(reversed, "revoke", 1)).toEqual(reversed)
  })
  it("the same notification twice changes nothing the second time", () => {
    const once = applyRefund(undefined, "revoke", 5)
    expect(applyRefund(once, "revoke", 5)).toEqual(once)
  })
})

describe("a notification is Apple's or it is nothing", () => {
  it("reads the event and the transaction from a genuine one", async () => {
    const result = await verifiedNotification(notification("REFUND").signedPayload, trustingTests)
    expect(result).toMatchObject({ type: "REFUND", transactionId: REFUNDED })
  })

  // Otherwise anybody could post a refund for somebody else's transaction and switch
  // their subscription off.
  it("the same notification is refused when only Apple is trusted", async () => {
    await expect(verifiedNotification(notification("REFUND").signedPayload, trustingApple)).rejects.toThrow()
  })

  // The one this whole file exists for. Somebody who was refunded holds their own
  // genuine purchase. Wrapped in a forged "refund reversed", it would give them back the
  // Pro they were refunded for, so the envelope has to be Apple's too, not just what is
  // inside it.
  it("a genuine purchase inside a forged envelope is refused", async () => {
    const envelope = forged({
      notificationType: "REFUND_REVERSED",
      notificationUUID: crypto.randomUUID(),
      version: "2.0",
      signedDate: Date.now(),
      data: { bundleId: BUNDLE, environment: "Sandbox", signedTransactionInfo: signed(purchase()) },
    })
    await expect(verifiedNotification(envelope, trustingTests)).rejects.toThrow()
  })

  it("one claiming to come from Xcode is refused", async () => {
    const xcode = notification("REFUND", purchase(), { data: { bundleId: BUNDLE, environment: "Xcode" } })
    await expect(verifiedNotification(xcode.signedPayload, trustingTests)).rejects.toThrow()
  })
})

describe("a refunded purchase stops working", () => {
  const refunded = async (id: string) => id === REFUNDED

  it("the refunded transaction is no longer Pro", async () => {
    expect((await entitlement(signed(purchase()), trustingTests, Date.now(), refunded)).subscriber).toBe(false)
  })

  // A refund is for one period. The same person subscribing again gets a new
  // transaction, and paying again has to work.
  it("a later purchase by the same person still is", async () => {
    const again = signed(purchase({ transactionId: "2000000000000002" }))
    expect((await entitlement(again, trustingTests, Date.now(), refunded)).subscriber).toBe(true)
  })

  // The purchase is already proven to be Apple's. The ledger is a second layer, and a
  // hiccup in it must not lock every paying subscriber out at once.
  it("a ledger that cannot be reached does not lock paying people out", async () => {
    const broken = async () => { throw new Error("storage unavailable") }
    expect((await entitlement(signed(purchase()), trustingTests, Date.now(), broken)).subscriber).toBe(true)
  })
})

describe("the endpoint Apple posts to", () => {
  it("records a genuine refund and says so with a 200", async () => {
    const { env } = fakeEnv()
    const response = await handleAppleNotification(post(notification("REFUND")), env, trustingTests)
    expect(response.status).toBe(200)
    expect(await isRevoked(env, REFUNDED)).toBe(true)
  })

  it("puts it back when Apple reverses the refund", async () => {
    const { env } = fakeEnv()
    await handleAppleNotification(post(notification("REFUND")), env, trustingTests)
    await handleAppleNotification(post(notification("REFUND_REVERSED")), env, trustingTests)
    expect(await isRevoked(env, REFUNDED)).toBe(false)
  })

  it("acknowledges what it ignores, and records nothing", async () => {
    const { env, ledgers } = fakeEnv()
    expect((await handleAppleNotification(post(notification("DID_RENEW")), env, trustingTests)).status).toBe(200)
    expect(ledgers.size).toBe(0)
  })

  // A 4xx makes Apple try again later, which is the right answer to a notification we
  // could not verify: if the cause is ours, the retry lands once it is fixed.
  it("refuses a forgery without recording it", async () => {
    const { env, ledgers } = fakeEnv()
    const response = await handleAppleNotification(post(notification("REFUND")), env, trustingApple)
    expect(response.status).toBe(401)
    expect(ledgers.size).toBe(0)
  })

  it("refuses a forged reversal of a real refund, and the refund stands", async () => {
    const { env } = fakeEnv()
    await handleAppleNotification(post(notification("REFUND")), env, trustingTests)
    const envelope = forged({
      notificationType: "REFUND_REVERSED",
      notificationUUID: crypto.randomUUID(),
      version: "2.0",
      signedDate: Date.now() + 1000,
      data: { bundleId: BUNDLE, environment: "Sandbox", signedTransactionInfo: signed(purchase()) },
    })
    expect((await handleAppleNotification(post({ signedPayload: envelope }), env, trustingTests)).status).toBe(401)
    expect(await isRevoked(env, REFUNDED)).toBe(true)
  })

  it("refuses a body with no signed payload", async () => {
    const { env } = fakeEnv()
    expect((await handleAppleNotification(post({}), env, trustingTests)).status).toBe(400)
    expect((await handleAppleNotification(new Request("https://proxy/x", { method: "POST", body: "not json" }), env, trustingTests)).status).toBe(400)
  })
})
