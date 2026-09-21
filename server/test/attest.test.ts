import { describe, expect, it } from "vitest"
import {
  APPLE_ROOT_SPKI,
  base64ToBytes,
  base64URLToBytes,
  bytesToBase64,
  concat,
  decodeCBOR,
  derChildren,
  publicKeyFromCertificate,
  rawSignature,
  readAuthenticatorData,
  readDER,
  sameBytes,
  verifyAssertion,
  verifyAttestation,
  verifyChain,
} from "../src/attest"

/**
 * The parts of App Attest that can be proven without an iPhone.
 *
 * A real attestation needs Apple's hardware, so the end-to-end path is only exercised on
 * a device. Everything underneath it is arithmetic on bytes and is testable here, which
 * matters more than usual: this is the control that decides whether a caller may spend
 * money, and a parser that quietly accepts a shape it does not understand is how a
 * forged payload gets waved through.
 */

/** CBOR for {"a": 1, "b": h'0102'}. */
const SMALL_MAP = Uint8Array.from([0xa2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x42, 0x01, 0x02])

describe("CBOR", () => {
  it("reads the shapes an attestation object is made of", () => {
    const decoded = decodeCBOR(SMALL_MAP) as Record<string, unknown>
    expect(decoded.a).toBe(1)
    expect(Array.from(decoded.b as Uint8Array)).toEqual([1, 2])
  })

  it("reads a text string", () => {
    // "apple-appattest"
    const bytes = Uint8Array.from([0x6f, ...new TextEncoder().encode("apple-appattest")])
    expect(decodeCBOR(bytes)).toBe("apple-appattest")
  })

  it("reads an array", () => {
    expect(decodeCBOR(Uint8Array.from([0x82, 0x01, 0x02]))).toEqual([1, 2])
  })

  it("refuses a type it does not understand rather than guessing", () => {
    // Major type 7 (floats and simple values) never appears here. A parser that
    // shrugged at it would be a parser that can be fed anything.
    expect(() => decodeCBOR(Uint8Array.from([0xf5]))).toThrow()
  })

  it("refuses a map key that is not a string", () => {
    expect(() => decodeCBOR(Uint8Array.from([0xa1, 0x01, 0x01]))).toThrow()
  })
})

describe("DER", () => {
  it("reads a short-form node", () => {
    const node = readDER(Uint8Array.from([0x04, 0x03, 0x01, 0x02, 0x03]))
    expect(node.tag).toBe(0x04)
    expect(Array.from(node.content)).toEqual([1, 2, 3])
    expect(node.end).toBe(5)
  })

  it("reads a long-form length", () => {
    // 0x81 says one length byte follows, which is how anything over 127 bytes arrives.
    const body = new Uint8Array(200).fill(7)
    const node = readDER(Uint8Array.from([0x04, 0x81, 200, ...body]))
    expect(node.content.length).toBe(200)
  })

  it("walks the children of a sequence", () => {
    const sequence = Uint8Array.from([0x30, 0x06, 0x02, 0x01, 0x05, 0x02, 0x01, 0x09])
    const children = derChildren(readDER(sequence))
    expect(children.map((child) => child.content[0])).toEqual([5, 9])
  })

  it("pulls the point out of a SubjectPublicKeyInfo", () => {
    // SEQUENCE { SEQUENCE { OID }, BIT STRING { 00 04 aa bb } }
    const spki = Uint8Array.from([
      0x30, 0x0e,
      0x30, 0x02, 0x06, 0x00,
      0x03, 0x05, 0x00, 0x04, 0xaa, 0xbb, 0xcc,
    ])
    const certificate = Uint8Array.from([0x30, spki.length + 2, 0x30, spki.length, ...spki])
    expect(Array.from(publicKeyFromCertificate(certificate))).toEqual([0x04, 0xaa, 0xbb, 0xcc])
  })
})

describe("signatures", () => {
  it("unwraps a DER signature into the raw pair WebCrypto wants", () => {
    // SEQUENCE { INTEGER 0x00aa..., INTEGER 0xbb }: the leading zero keeps r positive
    // and must not survive into the raw form.
    const der = Uint8Array.from([0x30, 0x08, 0x02, 0x02, 0x00, 0xaa, 0x02, 0x02, 0x00, 0xbb])
    const raw = rawSignature(der)
    expect(raw.length).toBe(64)
    expect(raw[31]).toBe(0xaa)
    expect(raw[63]).toBe(0xbb)
    // And the padding is zeros rather than whatever was in memory.
    expect(raw[0]).toBe(0)
    expect(raw[32]).toBe(0)
  })
})

describe("authenticator data", () => {
  it("reads the hash, the counter and the key id", () => {
    const data = new Uint8Array(100)
    data.set(new Uint8Array(32).fill(9), 0)
    new DataView(data.buffer).setUint32(33, 42)
    data[53] = 0
    data[54] = 4
    data.set([1, 2, 3, 4], 55)
    const parsed = readAuthenticatorData(data)
    expect(parsed.counter).toBe(42)
    expect(Array.from(parsed.credentialID)).toEqual([1, 2, 3, 4])
    expect(parsed.rpIdHash.every((byte) => byte === 9)).toBe(true)
  })
})

describe("refusals", () => {
  it("refuses an attestation that is not Apple's format", () => {
    // {"fmt": "none"}
    const bytes = Uint8Array.from([
      0xa1, 0x63, ...new TextEncoder().encode("fmt"),
      0x64, ...new TextEncoder().encode("none"),
    ])
    return expect(
      verifyAttestation({ attestation: bytes, challenge: "x", keyID: "AAAA", appID: "T.B" }),
    ).rejects.toThrow(/format/)
  })

  it("refuses an assertion whose counter did not advance", async () => {
    // A captured assertion replayed is the attack this counter exists to stop, and it
    // must fail before any cryptography is attempted.
    const authData = new Uint8Array(60)
    const appIDHash = new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode("T.B")),
    )
    authData.set(appIDHash, 0)
    new DataView(authData.buffer).setUint32(33, 5)
    const assertion = cborMap({
      authenticatorData: authData,
      signature: Uint8Array.from([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01]),
    })
    await expect(
      verifyAssertion({
        assertion,
        signedData: new Uint8Array([1]),
        key: { publicKey: "", counter: 5 },
        appID: "T.B",
      }),
    ).rejects.toThrow(/counter/)
  })

  it("refuses an assertion for a different app", async () => {
    const authData = new Uint8Array(60)
    new DataView(authData.buffer).setUint32(33, 99)
    const assertion = cborMap({
      authenticatorData: authData,
      signature: Uint8Array.from([0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01]),
    })
    await expect(
      verifyAssertion({
        assertion,
        signedData: new Uint8Array([1]),
        key: { publicKey: "", counter: 0 },
        appID: "T.B",
      }),
    ).rejects.toThrow(/app id/)
  })
})

describe("the chain to Apple", () => {
  it("refuses a certificate nobody signed", async () => {
    // The attack this exists to stop: a self-signed certificate carrying a correct
    // nonce and a correct app id hash. Every other check in this file passes on it.
    const forged = await selfSignedCertificate()
    expect(await verifyChain([forged])).toBe(false)
  })

  it("refuses an empty chain, and an absurdly long one", async () => {
    expect(await verifyChain([])).toBe(false)
    expect(await verifyChain(new Array(9).fill(new Uint8Array([0x30, 0x00])))).toBe(false)
  })

  it("pins Apple's real root rather than whatever is fetched at runtime", async () => {
    // If this ever fails to import, the constant has been corrupted, and the whole
    // control silently becomes "accept any certificate".
    const key = await crypto.subtle.importKey(
      "spki",
      base64ToBytes(APPLE_ROOT_SPKI),
      { name: "ECDSA", namedCurve: "P-384" },
      false,
      ["verify"],
    )
    expect((key.algorithm as { namedCurve?: string }).namedCurve).toBe("P-384")
  })
})

describe("bytes", () => {
  it("round-trips base64", () => {
    const bytes = Uint8Array.from([0, 1, 250, 255])
    expect(Array.from(base64ToBytes(bytesToBase64(bytes)))).toEqual([0, 1, 250, 255])
  })

  it("reads Apple's unpadded base64url key ids", () => {
    // "-_" rather than "+/", and no "=" on the end.
    expect(Array.from(base64URLToBytes("_-8"))).toEqual([0xff, 0xef])
  })

  it("compares without leaking through an early return", () => {
    expect(sameBytes(Uint8Array.from([1, 2]), Uint8Array.from([1, 2]))).toBe(true)
    expect(sameBytes(Uint8Array.from([1, 2]), Uint8Array.from([1, 3]))).toBe(false)
    expect(sameBytes(Uint8Array.from([1]), Uint8Array.from([1, 2]))).toBe(false)
  })

  it("joins two runs in order", () => {
    expect(Array.from(concat(Uint8Array.from([1]), Uint8Array.from([2, 3])))).toEqual([1, 2, 3])
  })
})

/** Minimal CBOR encoder, for fixtures only. */
function cborMap(entries: Record<string, Uint8Array>): Uint8Array {
  const parts: number[] = [0xa0 | Object.keys(entries).length]
  for (const [key, value] of Object.entries(entries)) {
    const name = new TextEncoder().encode(key)
    parts.push(0x60 | name.length, ...name)
    if (value.length < 24) parts.push(0x40 | value.length)
    else if (value.length < 256) parts.push(0x58, value.length)
    else parts.push(0x59, value.length >> 8, value.length & 0xff)
    parts.push(...value)
  }
  return Uint8Array.from(parts)
}


/**
 * A certificate signed by a key we just made up, which is exactly what an attacker
 * would present: correct in every respect except that Apple never saw it.
 */
async function selfSignedCertificate(): Promise<Uint8Array> {
  const pair = (await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  )) as CryptoKeyPair
  const exported = (await crypto.subtle.exportKey("spki", pair.publicKey)) as ArrayBuffer
  const spki = new Uint8Array(exported)
  // SEQUENCE { tbs, algorithm, BIT STRING signature }, where tbs holds the SPKI.
  const tbs = Uint8Array.from([0x30, spki.length, ...spki])
  const signature = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, pair.privateKey, tbs),
  )
  // Re-encoded as DER, which is the shape a certificate carries.
  const der = Uint8Array.from([
    0x30, 2 + 32 + 2 + 32,
    0x02, 32, ...signature.slice(0, 32),
    0x02, 32, ...signature.slice(32),
  ])
  const body = Uint8Array.from([...tbs, 0x30, 0x00, 0x03, der.length + 1, 0x00, ...der])
  return Uint8Array.from([0x30, 0x82, body.length >> 8, body.length & 0xff, ...body])
}
