/**
 * Is this caller actually a subscriber?
 *
 * The client sends the `jwsRepresentation` of a StoreKit 2 transaction. That string is
 * signed by Apple, so the server can decide entitlement without trusting a boolean from
 * the app and without building accounts.
 *
 * Two halves, and they are not equally finished. See `verifySignature`.
 */

export const PRODUCT_IDS = [
  "com.coachjett.ios.pro.monthly",
  "com.coachjett.ios.pro.yearly",
] as const

export interface TransactionPayload {
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

/**
 * Signature verification.
 *
 * NOT FINISHED, AND DELIBERATELY NOT FAKED. Verifying a StoreKit JWS properly means
 * validating the `x5c` certificate chain up to Apple's root CA and checking the leaf
 * before trusting its key. Hand-rolling X.509 chain validation is the kind of thing
 * that looks right and is not, and a bug here hands a free subscription to anyone who
 * can craft a token.
 *
 * Use Apple's own `app-store-server-library` (it runs under `nodejs_compat`) or an
 * audited JOSE library that does full chain validation against a pinned Apple root.
 * Until that is wired in, this throws rather than returning a permissive default, so a
 * half-built verifier cannot quietly grant entitlement in production.
 */
export async function verifySignature(_jws: string, allowUnverified: boolean): Promise<void> {
  if (allowUnverified) return
  throw new Error(
    "StoreKit JWS signature verification is not implemented. Wire in Apple's " +
      "app-store-server-library before enabling entitlement checks in production.",
  )
}

export async function entitlement(
  jws: string | undefined,
  bundleId: string,
  nowMs: number,
  allowUnverified: boolean,
): Promise<EntitlementResult> {
  if (!jws) return { subscriber: false, reason: "no transaction" }
  try {
    await verifySignature(jws, allowUnverified)
    return checkClaims(decodeJWSPayload(jws), bundleId, nowMs)
  } catch (error) {
    return { subscriber: false, reason: (error as Error).message }
  }
}
