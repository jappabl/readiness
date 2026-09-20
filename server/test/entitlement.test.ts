import { describe, expect, test } from "vitest"
import { checkClaims, decodeJWSPayload, entitlement, PRODUCT_IDS } from "../src/entitlement"

const BUNDLE = "com.coachjett.ios"
const NOW = 1_700_000_000_000

function jws(payload: unknown): string {
  const body = btoa(JSON.stringify(payload)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
  return `${btoa("{}")}.${body}.signature`
}

describe("reading a StoreKit transaction", () => {
  test("the payload round-trips out of the middle segment", () => {
    const decoded = decodeJWSPayload(jws({ bundleId: BUNDLE, productId: PRODUCT_IDS[0] }))
    expect(decoded.bundleId).toBe(BUNDLE)
  })

  test("anything that is not three segments is rejected", () => {
    expect(() => decodeJWSPayload("nonsense")).toThrow()
  })
})

describe("the claims that decide entitlement", () => {
  const live = { bundleId: BUNDLE, productId: PRODUCT_IDS[0], expiresDate: NOW + 86_400_000 }

  test("a live subscription is a subscriber", () => {
    expect(checkClaims(live, BUNDLE, NOW)).toEqual({ subscriber: true, productId: PRODUCT_IDS[0] })
  })

  test("a transaction from another app is not", () => {
    expect(checkClaims({ ...live, bundleId: "com.someone.else" }, BUNDLE, NOW).subscriber).toBe(false)
  })

  test("a product we do not sell is not", () => {
    expect(checkClaims({ ...live, productId: "com.coachjett.ios.pro.lifetime" }, BUNDLE, NOW).subscriber).toBe(false)
  })

  test("an expired subscription is not, including exactly at the boundary", () => {
    expect(checkClaims({ ...live, expiresDate: NOW - 1 }, BUNDLE, NOW).subscriber).toBe(false)
    expect(checkClaims({ ...live, expiresDate: NOW }, BUNDLE, NOW).subscriber).toBe(false)
  })

  test("a refund revokes it even while it looks unexpired", () => {
    const refunded = { ...live, revocationDate: NOW - 1000 }
    expect(checkClaims(refunded, BUNDLE, NOW)).toEqual({ subscriber: false, reason: "revoked" })
  })

  test("a transaction with no expiry is not trusted", () => {
    const { expiresDate, ...noExpiry } = live
    expect(checkClaims(noExpiry, BUNDLE, NOW).subscriber).toBe(false)
  })

  test("the yearly product counts too", () => {
    expect(checkClaims({ ...live, productId: PRODUCT_IDS[1] }, BUNDLE, NOW).subscriber).toBe(true)
  })
})

describe("the unverified-signature guard", () => {
  test("no transaction is not a subscriber", async () => {
    expect((await entitlement(undefined, BUNDLE, NOW, true)).subscriber).toBe(false)
  })

  test("a valid token is refused while signature checking is unimplemented", async () => {
    const token = jws({ bundleId: BUNDLE, productId: PRODUCT_IDS[0], expiresDate: NOW + 1000 })
    const result = await entitlement(token, BUNDLE, NOW, false)
    expect(result.subscriber).toBe(false)
    // The failure has to name itself, so nobody ships thinking this works.
    expect(result).toHaveProperty("reason", expect.stringContaining("not implemented"))
  })

  test("the same token passes only when unverified mode is explicitly allowed", async () => {
    const token = jws({ bundleId: BUNDLE, productId: PRODUCT_IDS[0], expiresDate: NOW + 1000 })
    expect((await entitlement(token, BUNDLE, NOW, true)).subscriber).toBe(true)
  })
})
