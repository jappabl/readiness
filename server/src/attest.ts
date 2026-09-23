/**
 * Verifying that a caller is a genuine build of this app on real hardware.
 *
 * This is the control that stops someone pointing curl at an endpoint which spends money
 * on every request. Everything else here (the meter, the free tier, the entitlement) is
 * arithmetic on top of an identity, and without this there is no identity: a shared
 * secret compiled into an IPA is a zip file away from being public.
 *
 * Apple's shape, in two steps:
 *
 *  1. **Attestation**, once per install. The device generates a key in the Secure
 *     Enclave and Apple returns a CBOR statement containing an X.509 chain rooted in
 *     Apple's App Attest CA. The leaf certificate carries an extension holding the
 *     nonce, which binds the statement to a challenge we issued. The authenticator data
 *     beside it carries SHA-256 of `<teamID>.<bundleID>` and the key id.
 *
 *  2. **Assertion**, per request. The same key signs SHA-256 of what is being sent, and
 *     a counter increments. We verify with the public key kept from step one.
 *
 * Written against the spec rather than a library, because the only dependency that would
 * do this is a general-purpose X.509 toolkit and the surface actually needed here is a
 * DER walk, one signature check, and a handful of equality tests.
 */

/**
 * Apple's App Attest root, pinned.
 *
 * The SubjectPublicKeyInfo of the certificate published at
 * https://www.apple.com/certificateauthority/Apple_App_Attestation_Root_CA.pem
 * (CN=Apple App Attestation Root CA, P-384). Pinned rather than fetched: a trust anchor
 * retrieved at runtime is a trust anchor an attacker only has to redirect, and this one
 * changes on the order of decades.
 *
 * This is the thing that makes the rest mean anything. Without it, the nonce and the app
 * id checks below pass against a certificate anybody can generate in a second.
 */
export const APPLE_ROOT_SPKI =
  "MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAERTHhmLW07ATaFQIEVwTtT4dyctdhNbJh" +
  "Fs/Ii2FdCgAHGbpphY3+d8qjuDngIN3WVhQUBHAoMeQ/cLiP1sOUtgjqK9auYen1" +
  "mMEvRq9Sk3Jm5X8U62H+xTD3FE9TgS41"

/** The OID that carries the nonce in the leaf certificate: 1.2.840.113635.100.8.2. */
const NONCE_OID = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02]

export interface AttestedKey {
  /** The raw 65-byte uncompressed EC public key point. */
  publicKey: string
  counter: number
}

// MARK: - CBOR, only as much as an attestation object needs

type CBOR = number | string | Uint8Array | CBOR[] | { [key: string]: CBOR }

/**
 * Enough CBOR to read one attestation object.
 *
 * Deliberately partial: maps with string keys, byte strings, text strings, arrays and
 * unsigned integers, which is everything Apple puts in this structure. Anything else
 * throws rather than being guessed at, because a parser that silently tolerates a shape
 * it does not understand is how a forged payload gets waved through.
 */
export function decodeCBOR(bytes: Uint8Array): CBOR {
  let offset = 0

  function readLength(info: number): number {
    if (info < 24) return info
    if (info === 24) return bytes[offset++]!
    if (info === 25) {
      const value = (bytes[offset]! << 8) | bytes[offset + 1]!
      offset += 2
      return value
    }
    if (info === 26) {
      const view = new DataView(bytes.buffer, bytes.byteOffset + offset, 4)
      offset += 4
      return view.getUint32(0)
    }
    throw new Error("unsupported CBOR length")
  }

  function read(): CBOR {
    const initial = bytes[offset++]!
    const major = initial >> 5
    const info = initial & 0x1f
    switch (major) {
      case 0:
        return readLength(info)
      case 2: {
        const length = readLength(info)
        const value = bytes.slice(offset, offset + length)
        offset += length
        return value
      }
      case 3: {
        const length = readLength(info)
        const value = new TextDecoder().decode(bytes.slice(offset, offset + length))
        offset += length
        return value
      }
      case 4: {
        const count = readLength(info)
        const items: CBOR[] = []
        for (let i = 0; i < count; i++) items.push(read())
        return items
      }
      case 5: {
        const count = readLength(info)
        const map: { [key: string]: CBOR } = {}
        for (let i = 0; i < count; i++) {
          const key = read()
          if (typeof key !== "string") throw new Error("non-string CBOR map key")
          map[key] = read()
        }
        return map
      }
      default:
        throw new Error(`unsupported CBOR major type ${major}`)
    }
  }

  return read()
}

// MARK: - DER, only as much as a certificate needs

interface DERNode {
  tag: number
  content: Uint8Array
  /** Where this node ends in the buffer it was read from. */
  end: number
}

export function readDER(bytes: Uint8Array, offset = 0): DERNode {
  const tag = bytes[offset]!
  let cursor = offset + 1
  let length = bytes[cursor++]!
  if (length & 0x80) {
    const count = length & 0x7f
    if (count === 0 || count > 4) throw new Error("unsupported DER length")
    length = 0
    for (let i = 0; i < count; i++) length = (length << 8) | bytes[cursor++]!
  }
  return { tag, content: bytes.slice(cursor, cursor + length), end: cursor + length }
}

/** Every child of a constructed DER node, in order. */
export function derChildren(node: DERNode): DERNode[] {
  const children: DERNode[] = []
  let offset = 0
  while (offset < node.content.length) {
    const child = readDER(node.content, offset)
    children.push(child)
    offset = child.end
  }
  return children
}

/**
 * The nonce Apple wrote into the leaf certificate.
 *
 * Found by walking the extensions for the App Attest OID rather than by position: the
 * order of extensions is not guaranteed, and indexing into them is the kind of thing
 * that works until Apple adds one.
 */
export function nonceFromCertificate(certificate: Uint8Array): Uint8Array | null {
  const found = findOID(readDER(certificate), NONCE_OID, 0)
  return found
}

function findOID(node: DERNode, oid: number[], depth: number): Uint8Array | null {
  if (depth > 12) return null
  const children = isConstructed(node.tag) ? derChildren(node) : []
  for (let i = 0; i < children.length; i++) {
    const child = children[i]!
    if (child.tag === 0x06 && sameBytes(child.content, Uint8Array.from(oid))) {
      // The value, skipping a `critical` BOOLEAN if this extension carries one.
      // X.509 puts it between the OID and the value, and "the node after the OID"
      // would have read the flag as the payload.
      const sibling = children.slice(i + 1).find((node) => node.tag === 0x04)
      if (!sibling) return null
      // Apple documents this as SEQUENCE { [1] { OCTET STRING nonce } }, and the octet
      // string is the payload, so the walk stops there rather than carrying on.
      //
      // Carrying on is how the previous two attempts at this were wrong. A list of the
      // container tags somebody thought of did not have [1] on it and stopped a level
      // early. Unwrapping every container instead went a level too far: a 32-byte hash
      // begins with an arbitrary byte, half of all bytes read as a constructed tag, and
      // the loop ate the nonce it had just found. A coin flip per attestation, which is
      // what it looked like from the outside.
      let inner = sibling.content
      for (let step = 0; step < 6; step++) {
        if (inner.length < 2) break
        const node = readDER(inner)
        if (node.tag === 0x04) return node.content
        if (!isConstructed(node.tag)) break
        inner = node.content
      }
      return inner
    }
    if (isConstructed(child.tag)) {
      const nested = findOID(child, oid, depth + 1)
      if (nested) return nested
    }
  }
  return null
}

function isConstructed(tag: number): boolean {
  return (tag & 0x20) !== 0
}

export function sameBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false
  let difference = 0
  for (let i = 0; i < a.length; i++) difference |= a[i]! ^ b[i]!
  return difference === 0
}

/**
 * Whether this chain really is Apple's.
 *
 * Each certificate must be signed by the next, and the last by the pinned root. The
 * signature covers the raw encoded tbsCertificate, tag and length included, which is why
 * the slice below is taken from the original buffer rather than rebuilt from the parsed
 * content.
 *
 * Deliberately not a general X.509 validator. There is no path building, no name
 * constraints and no revocation: the chain is two certificates deep, fixed in shape, and
 * issued minutes ago by hardware. What it does check is the only thing that can be
 * forged without Apple's private key, which is the signatures.
 */
export async function verifyChain(chain: Uint8Array[]): Promise<boolean> {
  if (chain.length < 1 || chain.length > 4) return false

  const rootKey = await crypto.subtle.importKey(
    "spki",
    base64ToBytes(APPLE_ROOT_SPKI),
    { name: "ECDSA", namedCurve: "P-384" },
    false,
    ["verify"],
  )

  for (let i = 0; i < chain.length; i++) {
    const certificate = chain[i]!
    const parentKey = chain[i + 1]
    const issuer = parentKey
      ? await crypto.subtle.importKey(
          "spki",
          spkiFromCertificate(parentKey),
          { name: "ECDSA", namedCurve: curveOf(parentKey) },
          false,
          ["verify"],
        )
      : rootKey
    if (!(await signedBy(certificate, issuer))) return false
  }
  return true
}

export async function signedBy(certificate: Uint8Array, issuer: CryptoKey): Promise<boolean> {
  const outer = readDER(certificate)
  // The signed bytes are the tbsCertificate exactly as encoded, not its contents.
  const tbs = readDER(outer.content, 0)
  const tbsStart = certificate.length - outer.content.length
  const signedBytes = certificate.slice(tbsStart, tbsStart + tbs.end)

  const children = derChildren(outer)
  const signatureNode = children[2]
  if (!signatureNode) return false
  // A BIT STRING's first byte is the count of unused bits.
  const der = signatureNode.content.slice(1)

  // Two different questions, and they used to share one answer.
  //
  // How wide r and s are is a property of the issuer's curve: a P-384 key signs with
  // 48-byte halves whatever it hashed. Which hash was used is a property of this
  // certificate, written in its own signatureAlgorithm, and Apple signs a P-256 leaf
  // with SHA-256 under a P-384 intermediate. Inferring the hash from the curve turned
  // every genuine chain into "chain does not reach Apple's root", which reads like a
  // forgery and was arithmetic.
  const named = (issuer.algorithm as { namedCurve?: string }).namedCurve
  const bits = named === "P-384" ? 48 : 32
  return crypto.subtle.verify(
    { name: "ECDSA", hash: hashOf(children[1]) },
    issuer,
    rawSignature(der, bits),
    signedBytes,
  )
}

/**
 * The hash named by a certificate's signatureAlgorithm.
 *
 * The ecdsa-with-SHA* OIDs differ only in their last byte: 1.2.840.10045.4.3.{2,3,4}
 * for SHA-256, SHA-384 and SHA-512.
 */
function hashOf(algorithm: DERNode | undefined): string {
  const oid = algorithm && derChildren(algorithm)[0]
  const last = oid?.content[oid.content.length - 1]
  switch (last) {
    case 3:
      return "SHA-384"
    case 4:
      return "SHA-512"
    default:
      return "SHA-256"
  }
}

/**
 * The whole SubjectPublicKeyInfo, which is what WebCrypto's "spki" format wants.
 *
 * From `offset`, which is where the node begins, and not from `end - content.length`,
 * which is where its *contents* begin. The second skipped the SEQUENCE's own tag and
 * length, so what came back was the inside of an SPKI rather than an SPKI, and every
 * real device was turned away with "invalid SPKI input". Nothing caught it because the
 * chain tests only ever fed this rubbish and watched it say no.
 */
export function spkiFromCertificate(certificate: Uint8Array): Uint8Array {
  const tbs = derChildren(readDER(certificate))[0]
  if (!tbs) throw new Error("no tbsCertificate")
  let offset = 0
  while (offset < tbs.content.length) {
    const node = readDER(tbs.content, offset)
    if (node.tag === 0x30) {
      const parts = derChildren(node)
      if (parts.length === 2 && parts[1]?.tag === 0x03) {
        return tbs.content.slice(offset, node.end)
      }
    }
    offset = node.end
  }
  throw new Error("no public key in certificate")
}

function curveOf(certificate: Uint8Array): "P-256" | "P-384" {
  // The point's length says which curve it is: 65 bytes for P-256, 97 for P-384.
  return publicKeyFromCertificate(certificate).length > 70 ? "P-384" : "P-256"
}

/** The uncompressed EC point from a certificate's SubjectPublicKeyInfo. */
export function publicKeyFromCertificate(certificate: Uint8Array): Uint8Array {
  const tbs = derChildren(readDER(certificate))[0]
  if (!tbs) throw new Error("no tbsCertificate")
  for (const child of derChildren(tbs)) {
    if (child.tag !== 0x30) continue
    const parts = derChildren(child)
    // SubjectPublicKeyInfo is the SEQUENCE whose second element is a BIT STRING.
    if (parts.length === 2 && parts[1]?.tag === 0x03) {
      // A BIT STRING's first byte counts unused bits, which is zero for a key.
      return parts[1]!.content.slice(1)
    }
  }
  throw new Error("no public key in certificate")
}

// MARK: - The two checks

export interface AuthenticatorData {
  /** SHA-256 of "<teamID>.<bundleID>". */
  rpIdHash: Uint8Array
  counter: number
  /** The key id Apple assigned, which must match the one the client claims. */
  credentialID: Uint8Array
}

export function readAuthenticatorData(bytes: Uint8Array): AuthenticatorData {
  const view = new DataView(bytes.buffer, bytes.byteOffset)
  return {
    rpIdHash: bytes.slice(0, 32),
    counter: view.getUint32(33),
    // 37 header, 16 AAGUID, 2 length, then the id itself.
    credentialID: bytes.slice(55, 55 + ((bytes[53]! << 8) | bytes[54]!)),
  }
}

/**
 * Exactly what a request's signature covers: the challenge, the body, and the
 * fingerprint of the purchase it carries, if it carries one.
 *
 * The purchase travels in a header, and a header nobody signed can be swapped by anyone
 * who can watch their own traffic: one subscriber's proof, everybody's Pro. No purchase
 * leaves the message exactly as it was before, so builds that never bought anything
 * keep working. Pinned byte for byte against the app's `AssertionMessage` by a shared
 * test vector.
 */
export async function assertionMessage(
  challenge: string,
  body: Uint8Array,
  purchase: string | null,
): Promise<Uint8Array> {
  const head = new TextEncoder().encode(challenge)
  const tail = purchase ? await sha256(new TextEncoder().encode(purchase)) : new Uint8Array(0)
  const message = new Uint8Array(head.length + body.length + tail.length)
  message.set(head)
  message.set(body, head.length)
  message.set(tail, head.length + body.length)
  return message
}

export async function sha256(data: Uint8Array): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", data))
}

async function importKey(point: Uint8Array): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "raw",
    point,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  )
}

/** ECDSA signatures arrive DER-encoded and WebCrypto wants the raw 64 bytes. */
export function rawSignature(der: Uint8Array, bits = 32): Uint8Array {
  const [r, s] = derChildren(readDER(der))
  if (!r || !s) throw new Error("malformed signature")
  const out = new Uint8Array(bits * 2)
  const put = (value: Uint8Array, at: number) => {
    // Strip a leading zero added to keep the integer positive, then right-align.
    const trimmed = value[0] === 0 ? value.slice(1) : value
    out.set(trimmed.slice(-bits), at + Math.max(0, bits - trimmed.length))
  }
  put(r.content, 0)
  put(s.content, bits)
  return out
}

/**
 * Step one. Returns the key to keep, or throws with the reason it was refused.
 */
export async function verifyAttestation(options: {
  attestation: Uint8Array
  challenge: string
  keyID: string
  appID: string
}): Promise<AttestedKey> {
  const object = decodeCBOR(options.attestation)
  if (typeof object !== "object" || object === null || Array.isArray(object)) {
    throw new Error("attestation is not a map")
  }
  const map = object as { [key: string]: CBOR }
  if (map.fmt !== "apple-appattest") throw new Error("unexpected attestation format")

  const statement = map.attStmt as { [key: string]: CBOR }
  const chain = statement.x5c as Uint8Array[]
  const leaf = chain?.[0]
  if (!leaf) throw new Error("no leaf certificate")

  // First, and before anything is read out of it: a certificate that does not chain to
  // Apple's root is one anybody could have written, nonce and all.
  if (!(await verifyChain(chain))) throw new Error("chain does not reach Apple's root")

  const authData = map.authData as Uint8Array
  const auth = readAuthenticatorData(authData)

  // The statement is bound to a challenge we issued, so it cannot be replayed.
  const clientDataHash = await sha256(new TextEncoder().encode(options.challenge))
  const expectedNonce = await sha256(concat(authData, clientDataHash))
  const nonce = nonceFromCertificate(leaf)
  if (!nonce || !sameBytes(nonce, expectedNonce)) throw new Error("nonce mismatch")

  // And to this app, rather than any app of Apple's.
  const appIDHash = await sha256(new TextEncoder().encode(options.appID))
  if (!sameBytes(auth.rpIdHash, appIDHash)) throw new Error("app id mismatch")

  // And to the key the client says it is using.
  const claimed = base64URLToBytes(options.keyID)
  if (!sameBytes(auth.credentialID, claimed)) throw new Error("key id mismatch")

  return {
    publicKey: bytesToBase64(publicKeyFromCertificate(leaf)),
    // Apple's own counter starts at zero; the first assertion must exceed it.
    counter: auth.counter,
  }
}

/**
 * Step two. Returns the counter to store, or throws.
 *
 * The counter is the replay defence: it only ever goes up, so a captured assertion
 * cannot be used twice even against the same body.
 */
export async function verifyAssertion(options: {
  assertion: Uint8Array
  signedData: Uint8Array
  key: AttestedKey
  appID: string
}): Promise<number> {
  const object = decodeCBOR(options.assertion)
  const map = object as { [key: string]: CBOR }
  const signature = map.signature as Uint8Array
  const authData = map.authenticatorData as Uint8Array
  if (!signature || !authData) throw new Error("malformed assertion")

  const auth = readAuthenticatorData(authData)
  const appIDHash = await sha256(new TextEncoder().encode(options.appID))
  if (!sameBytes(auth.rpIdHash, appIDHash)) throw new Error("app id mismatch")
  if (auth.counter <= options.key.counter) throw new Error("counter did not advance")

  const clientDataHash = await sha256(options.signedData)
  const payload = await sha256(concat(authData, clientDataHash))
  const verified = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    await importKey(base64ToBytes(options.key.publicKey)),
    rawSignature(signature),
    payload,
  )
  if (!verified) throw new Error("signature did not verify")
  return auth.counter
}

// MARK: - Bytes

export function concat(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length)
  out.set(a)
  out.set(b, a.length)
  return out
}

export function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value)
  return Uint8Array.from(binary, (character) => character.charCodeAt(0))
}

export function bytesToBase64(bytes: Uint8Array): string {
  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary)
}

/** Apple's key ids are base64url without padding. */
export function base64URLToBytes(value: string): Uint8Array {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/")
  return base64ToBytes(padded + "=".repeat((4 - (padded.length % 4)) % 4))
}
