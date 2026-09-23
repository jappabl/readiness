/**
 * Signs StoreKit data for real, with a chain made for these tests alone
 * (test/fixtures/storekit). It carries Apple's certificate markers, so it takes the
 * whole path Apple's library takes, and it is trusted only when a test passes TEST_ROOT
 * in. Production trusts Apple's root and nothing else.
 *
 * The test certificates run to 2046. Signing uses the real clock, because the library
 * judges certificate validity at the data's own signedDate.
 */
import { Buffer } from "node:buffer"
import { createPrivateKey, generateKeyPairSync, sign } from "node:crypto"
import { readFileSync } from "node:fs"

const fixture = (file: string) =>
  decodeURIComponent(new URL(`./fixtures/storekit/${file}`, import.meta.url).pathname)
const pemBody = (file: string) => readFileSync(fixture(file), "utf8").replace(/-----[^-]+-----|\s/g, "")
const LEAF_KEY = createPrivateKey(readFileSync(fixture("leaf.pkcs8.pem")))

export const CHAIN = [pemBody("leaf.pem"), pemBody("int.pem"), pemBody("root.pem")]
export const TEST_ROOT = pemBody("root.pem")
export const BUNDLE = "com.coachjett.ios"

export function signed(payload: object, chain: string[] = CHAIN): string {
  const header = Buffer.from(JSON.stringify({ alg: "ES256", x5c: chain })).toString("base64url")
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url")
  const signature = Buffer.from(
    sign("sha256", Buffer.from(`${header}.${body}`), { key: LEAF_KEY, dsaEncoding: "ieee-p1363" }),
  ).toString("base64url")
  return `${header}.${body}.${signature}`
}

export function purchase(overrides: object = {}) {
  const now = Date.now()
  return {
    transactionId: "2000000000000001",
    originalTransactionId: "2000000000000001",
    bundleId: BUNDLE,
    productId: "com.coachjett.ios.pro.monthly",
    purchaseDate: now - 86_400_000,
    expiresDate: now + 30 * 86_400_000,
    signedDate: now,
    environment: "Sandbox",
    type: "Auto-Renewable Subscription",
    inAppOwnershipType: "PURCHASED",
    ...overrides,
  }
}

/**
 * A forgery done properly: the trusted chain copied into the header, as anybody can,
 * and the whole thing signed with a key of the forger's own. Only the signature is
 * wrong, so this is what catches a verifier that reads the certificates and never
 * checks that they signed anything.
 */
export function forged(payload: object): string {
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" })
  const header = Buffer.from(JSON.stringify({ alg: "ES256", x5c: CHAIN })).toString("base64url")
  const body = Buffer.from(JSON.stringify(payload)).toString("base64url")
  const signature = Buffer.from(
    sign("sha256", Buffer.from(`${header}.${body}`), { key: privateKey, dsaEncoding: "ieee-p1363" }),
  ).toString("base64url")
  return `${header}.${body}.${signature}`
}

/** An App Store Server Notification, version 2, as Apple posts it. */
export function notification(notificationType: string, transaction: object = purchase(), overrides: object = {}) {
  return {
    signedPayload: signed({
      notificationType,
      notificationUUID: crypto.randomUUID(),
      version: "2.0",
      signedDate: Date.now(),
      data: {
        bundleId: BUNDLE,
        environment: "Sandbox",
        signedTransactionInfo: signed(transaction),
      },
      ...overrides,
    }),
  }
}
