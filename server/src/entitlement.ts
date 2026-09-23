/**
 * Is this caller actually a subscriber?
 *
 * The client sends the `jwsRepresentation` of a StoreKit 2 transaction. That string is
 * signed by Apple, so the server can decide entitlement without trusting a boolean from
 * the app and without building accounts.
 *
 * Two halves: `verifiedPayload` proves Apple signed it, then `checkClaims` decides
 * whether what Apple signed is a live subscription to this app.
 */
import { Buffer } from "node:buffer"

export const PRODUCT_IDS = [
  "com.coachjett.ios.pro.monthly",
  "com.coachjett.ios.pro.yearly",
  // The founding hundred pay less for the same thing, which App Store Connect can
  // only express as a separate product in the same group. It has to be named here or
  // the people who paid first are the only ones the server calls freeloaders.
  "com.coachjett.ios.pro.yearly.founding",
] as const

export interface TransactionPayload {
  /** One billing period's purchase. A renewal or a new subscription gets a new one. */
  transactionId?: string
  bundleId?: string
  productId?: string
  /** Epoch milliseconds. */
  expiresDate?: number
  purchaseDate?: number
  revocationDate?: number
  environment?: string
}

export type EntitlementResult =
  | { subscriber: true; productId: string }
  | { subscriber: false; reason: string }

function base64UrlToBytes(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/")
  const binary = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4))
  return Uint8Array.from(binary, (c) => c.charCodeAt(0))
}

export function decodeJWSPayload(jws: string): TransactionPayload {
  const parts = jws.split(".")
  if (parts.length !== 3) throw new Error("not a JWS")
  const body = parts[1]
  if (!body) throw new Error("no payload")
  return JSON.parse(new TextDecoder().decode(base64UrlToBytes(body))) as TransactionPayload
}

/**
 * The claim checks. Pure, and the part that is easy to get subtly wrong in ways tests
 * catch: a transaction for a different app, for a product we do not sell, already
 * expired, or refunded.
 */
export function checkClaims(
  payload: TransactionPayload,
  bundleId: string,
  nowMs: number,
): EntitlementResult {
  if (payload.bundleId !== bundleId) return { subscriber: false, reason: "wrong bundle" }

  const productId = payload.productId
  if (!productId || !(PRODUCT_IDS as readonly string[]).includes(productId)) {
    return { subscriber: false, reason: "unknown product" }
  }
  // A refund revokes the entitlement even though the expiry has not passed.
  if (payload.revocationDate !== undefined && payload.revocationDate <= nowMs) {
    return { subscriber: false, reason: "revoked" }
  }
  if (payload.expiresDate === undefined) return { subscriber: false, reason: "no expiry" }
  if (payload.expiresDate <= nowMs) return { subscriber: false, reason: "expired" }

  return { subscriber: true, productId }
}

/** What to trust, and which app this is. */
export interface Trust {
  bundleId: string
  /** Base64 DER. Production passes Apple's root and nothing else. */
  roots: string[]
  /**
   * The app's numeric Apple ID from App Store Connect. Apple's library refuses to check
   * a production purchase without it, so until it is configured production purchases
   * fail closed. Sandbox purchases, which is everything TestFlight makes, do not need it.
   */
  appAppleId?: number
}

/**
 * Checked by Apple's own library rather than by anything written here. Validating the
 * certificate chain up to Apple's root is the kind of code that looks right and is not,
 * and a mistake in it hands a free subscription to anybody who can build a token.
 *
 * Imported inside the call, not at the top of the file: a dependency of Apple's library
 * generates random values the moment it loads, and the Workers runtime refuses that at
 * global scope. Loaded here, it runs inside a request, which is allowed.
 *
 * Online checks are off. On, every coach message would wait on a round trip to Apple's
 * certificate status service, and what it guards against is Apple revoking its own
 * intermediate. Off, certificate validity is judged at the transaction's signed date,
 * which the signature covers.
 */
export async function verifierFor(claimedEnvironment: unknown, trust: Trust) {
  // The environment is read before anything is verified, and used for one thing only:
  // which of Apple's two environments to check against. Every other environment is
  // refused, because Apple's library skips the signature entirely for Xcode and local
  // testing, and routing data that merely claims to be from Xcode there would be a
  // free pass.
  if (claimedEnvironment !== "Sandbox" && claimedEnvironment !== "Production") {
    throw new Error("unsupported environment")
  }
  const { SignedDataVerifier, Environment } = await import("@apple/app-store-server-library")
  return new SignedDataVerifier(
    trust.roots.map((root) => Buffer.from(root, "base64")),
    false,
    claimedEnvironment === "Production" ? Environment.PRODUCTION : Environment.SANDBOX,
    trust.bundleId,
    trust.appAppleId,
  )
}

async function verifiedPayload(jws: string, trust: Trust): Promise<TransactionPayload> {
  const verifier = await verifierFor(decodeJWSPayload(jws).environment, trust)
  const payload = await verifier.verifyAndDecodeTransaction(jws)
  return {
    transactionId: payload.transactionId,
    bundleId: payload.bundleId,
    productId: payload.productId,
    expiresDate: payload.expiresDate,
    purchaseDate: payload.purchaseDate,
    revocationDate: payload.revocationDate,
    environment: payload.environment,
  }
}

/**
 * `refunded` answers whether Apple has since refunded this transaction. The purchase a
 * phone holds is signed before any refund and stays valid until its period ends, so
 * without it somebody could buy a year, get their money back, and keep Pro for the year.
 */
export async function entitlement(
  jws: string | undefined,
  trust: Trust,
  nowMs: number,
  refunded: (transactionId: string) => Promise<boolean> = async () => false,
): Promise<EntitlementResult> {
  if (!jws) return { subscriber: false, reason: "no transaction" }
  try {
    const payload = await verifiedPayload(jws, trust)
    const result = checkClaims(payload, trust.bundleId, nowMs)
    if (!result.subscriber || !payload.transactionId) return result
    // A second layer over a purchase Apple has already vouched for. If it cannot be
    // read, the purchase stands: a storage hiccup must not lock every paying subscriber
    // out at once, and the worst it lets through is a refund for as long as it lasts.
    const wasRefunded = await refunded(payload.transactionId).catch(() => false)
    return wasRefunded ? { subscriber: false, reason: "refunded" } : result
  } catch (error) {
    // Apple's exceptions carry a status rather than a message, and neither reaches the
    // client. Refusal is the only outcome that matters here.
    return { subscriber: false, reason: error instanceof Error && error.message ? error.message : "not verified" }
  }
}
