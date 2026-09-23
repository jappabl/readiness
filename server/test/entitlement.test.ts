import { Buffer } from "node:buffer"
import { createHash, createPrivateKey, sign } from "node:crypto"
import { readFileSync } from "node:fs"
import { describe, expect, test } from "vitest"
import { APPLE_ROOT_G3 } from "../src/apple-root"
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

  // The founder product is a third product in the same subscription group, not a
  // discount applied to the yearly one, so it arrives with its own id. A list that
  // does not name it tells the first hundred people they are not subscribers.
  test("the founding yearly product counts too", () => {
    const founding = { ...live, productId: "com.coachjett.ios.pro.yearly.founding" }
    expect(checkClaims(founding, BUNDLE, NOW).subscriber).toBe(true)
  })
})

/**
 * Signed for real, by a chain generated for these tests alone (test/fixtures/storekit).
 * It carries the same certificate markers Apple's does, so it exercises the whole path
 * Apple's library takes, and it is trusted only when a test passes it in. Production
 * trusts Apple's root and nothing else.
 *
 * The test certificates run to 2046; signing uses the real clock because the library
 * judges certificate validity at the transaction's own signedDate.
 */
const fixture = (file: string) => decodeURIComponent(new URL(`./fixtures/storekit/${file}`, import.meta.url).pathname)
const pemBody = (file: string) => readFileSync(fixture(file), "utf8").replace(/-----[^-]+-----|\s/g, "")
const LEAF_KEY = createPrivateKey(readFileSync(fixture("leaf.pkcs8.pem")))
const CHAIN = [pemBody("leaf.pem"), pemBody("int.pem"), pemBody("root.pem")]
const TEST_ROOT = pemBody("root.pem")

function signed(payload: object, chain: string[] = CHAIN): string {
  const header = Buffer.from(JSON.stringify({ alg: "ES256", x5c: chain })).toString("base64url")
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url")
  const signature = Buffer.from(
    sign("sha256", Buffer.from(`${header}.${body}`), { key: LEAF_KEY, dsaEncoding: "ieee-p1363" }),
  ).toString("base64url")
  return `${header}.${body}.${signature}`
}

function purchase(overrides: object = {}) {
  const now = Date.now()
  return {
    transactionId: "2000000000000001",
    originalTransactionId: "2000000000000001",
    bundleId: BUNDLE,
    productId: PRODUCT_IDS[0],
    purchaseDate: now - 86_400_000,
    expiresDate: now + 30 * 86_400_000,
    signedDate: now,
    environment: "Sandbox",
    type: "Auto-Renewable Subscription",
    inAppOwnershipType: "PURCHASED",
    ...overrides,
  }
}

const trustingTests = { bundleId: BUNDLE, roots: [TEST_ROOT] }
const trustingApple = { bundleId: BUNDLE, roots: [APPLE_ROOT_G3] }

describe("verifying that Apple really sold this", () => {
  test("no transaction is not a subscriber", async () => {
    expect((await entitlement(undefined, trustingApple, Date.now())).subscriber).toBe(false)
  })

  test("a purchase signed by a trusted chain is a subscriber", async () => {
    const result = await entitlement(signed(purchase()), trustingTests, Date.now())
    expect(result).toEqual({ subscriber: true, productId: PRODUCT_IDS[0] })
  })

  // The one that matters. Anybody can build a chain that looks like Apple's; only a
  // chain that ends at Apple's root is Apple's. Production trusts nothing else.
  test("the same purchase is refused when only Apple is trusted", async () => {
    const result = await entitlement(signed(purchase()), trustingApple, Date.now())
    expect(result.subscriber).toBe(false)
  })

  test("a purchase edited after it was signed is refused", async () => {
    const [header, , signature] = signed(purchase()).split(".")
    const edited = Buffer.from(JSON.stringify(purchase({ productId: PRODUCT_IDS[1] }))).toString("base64url")
    expect((await entitlement(`${header}.${edited}.${signature}`, trustingTests, Date.now())).subscriber).toBe(false)
  })

  test("the old unsigned shape is refused", async () => {
    const unsigned = jws({ bundleId: BUNDLE, productId: PRODUCT_IDS[0], expiresDate: Date.now() + 1000 })
    expect((await entitlement(unsigned, trustingTests, Date.now())).subscriber).toBe(false)
  })

  test("a chain of the wrong length is refused", async () => {
    expect((await entitlement(signed(purchase(), CHAIN.slice(0, 2)), trustingTests, Date.now())).subscriber).toBe(false)
  })

  // Apple's library skips the signature entirely for Xcode and local-testing purchases,
  // because nothing signed them. A purchase that says it came from Xcode must never be
  // routed to that path, or claiming to be Xcode is a free subscription.
  test("a purchase claiming to come from Xcode is refused", async () => {
    for (const environment of ["Xcode", "LocalTesting", undefined, "Nonsense"]) {
      const result = await entitlement(signed(purchase({ environment })), trustingTests, Date.now())
      expect(result.subscriber, String(environment)).toBe(false)
    }
  })

  test("a production purchase is refused until the app's Apple ID is configured", async () => {
    const production = signed(purchase({ environment: "Production" }))
    expect((await entitlement(production, trustingTests, Date.now())).subscriber).toBe(false)
    expect((await entitlement(production, { ...trustingTests, appAppleId: 1234567890 }, Date.now())).subscriber).toBe(true)
  })

  test("a genuine purchase for another app is refused", async () => {
    const other = signed(purchase({ bundleId: "com.someone.else" }))
    expect((await entitlement(other, trustingTests, Date.now())).subscriber).toBe(false)
  })

  test("a genuine purchase that has expired is refused", async () => {
    const lapsed = signed(purchase({ expiresDate: Date.now() - 1000 }))
    expect((await entitlement(lapsed, trustingTests, Date.now())).subscriber).toBe(false)
  })

  // Pinned, so the root cannot be swapped without a test noticing. Checked against both
  // the root macOS ships and the file Apple serves at apple.com/certificateauthority.
  test("the trusted root is Apple Root CA - G3", async () => {
    const digest = createHash("sha256").update(Buffer.from(APPLE_ROOT_G3, "base64")).digest("hex")
    expect(digest).toBe("63343abfb89a6a03ebb57e9b3f5fa7be7c4f5c756f3017b3a8c488c3653e9179")
  })
})
