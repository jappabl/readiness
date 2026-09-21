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
  nonceFromCertificate,
  spkiFromCertificate,
  signedBy,
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

/// Real certificates, because the chain tests only ever fed it rubbish and watched it
/// say no. Saying no to rubbish is not the same as saying yes to Apple: the one path
/// nothing covered was reading a genuine certificate's public key, and it was broken.
/// A P-384 root signing a P-256 leaf, which is the shape Apple actually sends.
const TEST_ROOT_DER = "MIIBuTCCAUCgAwIBAgIUE3UcdzJ+cQDUhsGpOZCJrWOMYDMwCgYIKoZIzj0EAwMwFDESMBAGA1UEAwwJVGVzdCBSb290MB4XDTI2MDkyMTE3MTg0NVoXDTM2MDkxODE3MTg0NVowFDESMBAGA1UEAwwJVGVzdCBSb290MHYwEAYHKoZIzj0CAQYFK4EEACIDYgAEtGI0YUdB4pmaXb/Unf+VTq0vp7b2uoJBPWXkKyI0BsjcCG6O659dyZ8c4DT9m+i7bdNZslcuqN4MKcWRT6IOoJkribgI1XdouX0VtWlxR3kWL2Jy/Bg2+LJA5MiiJd8to1MwUTAdBgNVHQ4EFgQUkHVoSjKNiJb0DChyHD20THgJq7EwHwYDVR0jBBgwFoAUkHVoSjKNiJb0DChyHD20THgJq7EwDwYDVR0TAQH/BAUwAwEB/zAKBggqhkjOPQQDAwNnADBkAjBXHEW3zJkQP0D7NBNiatjuNTrzyomX8vyb1mutVQKwEqxwCUh+UlyjVFKFoIBqVvECMDmSJrBQ45R2yocn4zzAlGY+Up6U1zeik2Ty7ELqbdXOKUQ2m1VAqt/sHPEgjBtASQ=="
const TEST_LEAF_SHA256_DER = "MIIBeDCB/6ADAgECAgECMAoGCCqGSM49BAMCMBQxEjAQBgNVBAMMCVRlc3QgUm9vdDAeFw0yNjA5MjExNzIwNTNaFw0zNjA5MTgxNzIwNTNaMBQxEjAQBgNVBAMMCVRlc3QgTGVhZjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABDJxchydrT+fJqutWeIqV7OPtt3e+Y+Hqqs2KWZ7JZSxpmC5WQjpYjtHutUZMrWkXUaN1RiyyIOi1Jx2eoNPwnejQjBAMB0GA1UdDgQWBBSfLJ/j4ED+6vNmRnYFW+ehV0NYbDAfBgNVHSMEGDAWgBSQdWhKMo2IlvQMKHIcPbRMeAmrsTAKBggqhkjOPQQDAgNoADBlAjEAkoTxTLrp3mNAtTinUQ35UZN6qLBx0kfFkWDzEFmgV3PbS46oS999fK7Vf+1L+ubRAjBQra3RI2L9C/ZuiWpc5j3iXiNchRfgplmvOBKYeMTokrh2/QZNgQ13dGff6GrmKxs="
const TEST_LEAF_DER = "MIIBeDCB/6ADAgECAgEBMAoGCCqGSM49BAMDMBQxEjAQBgNVBAMMCVRlc3QgUm9vdDAeFw0yNjA5MjExNzE4NDVaFw0zNjA5MTgxNzE4NDVaMBQxEjAQBgNVBAMMCVRlc3QgTGVhZjBZMBMGByqGSM49AgEGCCqGSM49AwEHA0IABDJxchydrT+fJqutWeIqV7OPtt3e+Y+Hqqs2KWZ7JZSxpmC5WQjpYjtHutUZMrWkXUaN1RiyyIOi1Jx2eoNPwnejQjBAMB0GA1UdDgQWBBSfLJ/j4ED+6vNmRnYFW+ehV0NYbDAfBgNVHSMEGDAWgBSQdWhKMo2IlvQMKHIcPbRMeAmrsTAKBggqhkjOPQQDAwNoADBlAjBAjmHF8w7ZTWbfqk0MC11Gz+bdRE9dE80EaQDm5VsMrh2E96T8dSi+1efbaY/0le0CMQCCgQmEFJavgyk5WrNh4mNgB4lepDDlnG47HTKtl6FLRbz8+tNOx0oymYqs1qE7qf8="

/// Apple's nonce extension, built the way Apple builds it.
///
/// extnValue is an OCTET STRING holding SEQUENCE { [1] { OCTET STRING nonce } }. The
/// context tag is [1], and the unwrapper knew [0]. It stopped one level early and
/// returned the [1] node with its header still on, so every genuine attestation was
/// refused with "nonce mismatch": a sentence that means somebody replayed a statement,
/// and here meant a tag number.
function der(tag: number, content: Uint8Array): Uint8Array {
  if (content.length < 0x80) return Uint8Array.from([tag, content.length, ...content])
  return Uint8Array.from([tag, 0x81, content.length, ...content])
}

describe("Apple's nonce extension", () => {
  const nonce = Uint8Array.from({ length: 32 }, (_, i) => i + 1)
  const NONCE_OID = Uint8Array.from([0x2a, 0x86, 0x48, 0x86, 0xf7, 0x63, 0x64, 0x08, 0x02])

  function certificateCarrying(value: Uint8Array): Uint8Array {
    const extension = new Uint8Array([...der(0x06, NONCE_OID), ...der(0x04, value)])
    return der(0x30, der(0x30, extension))
  }

  it("reads the nonce out of a [1]-wrapped extension", () => {
    const wrapped = der(0x30, der(0xa1, der(0x04, nonce)))
    expect(nonceFromCertificate(certificateCarrying(wrapped))).toEqual(nonce)
  })

  it("still reads a [0]-wrapped one", () => {
    const wrapped = der(0x30, der(0xa0, der(0x04, nonce)))
    expect(nonceFromCertificate(certificateCarrying(wrapped))).toEqual(nonce)
  })
})

describe("reading a real certificate", () => {
  it("hands WebCrypto a SubjectPublicKeyInfo it will accept", async () => {
    // The whole structure, tag and length included. Returning only the contents threw
    // "invalid SPKI input" against every real device, and against nothing in this file.
    const spki = spkiFromCertificate(base64ToBytes(TEST_ROOT_DER))
    expect(spki[0]).toBe(0x30)
    await expect(
      crypto.subtle.importKey("spki", spki, { name: "ECDSA", namedCurve: "P-384" }, false, [
        "verify",
      ]),
    ).resolves.toBeDefined()
  })

  it("reads a P-256 leaf's key as well as a P-384 issuer's", async () => {
    const spki = spkiFromCertificate(base64ToBytes(TEST_LEAF_DER))
    await expect(
      crypto.subtle.importKey("spki", spki, { name: "ECDSA", namedCurve: "P-256" }, false, [
        "verify",
      ]),
    ).resolves.toBeDefined()
  })

  /// The shape Apple actually sends: a P-384 issuer signing a P-256 leaf with SHA-256.
  /// The hash a signature used is written in the certificate's own signatureAlgorithm
  /// and was being inferred from the issuer's curve instead, so this exact combination
  /// verified against SHA-384 and failed. Every real chain reached "chain does not
  /// reach Apple's root", which reads like a forgery and was arithmetic.
  it("verifies a SHA-256 leaf signed by a P-384 issuer", async () => {
    const issuer = await crypto.subtle.importKey(
      "spki",
      spkiFromCertificate(base64ToBytes(TEST_ROOT_DER)),
      { name: "ECDSA", namedCurve: "P-384" },
      false,
      ["verify"],
    )
    expect(await signedBy(base64ToBytes(TEST_LEAF_SHA256_DER), issuer)).toBe(true)
  })

  it("verifies a leaf against the issuer that really signed it", async () => {
    const issuer = await crypto.subtle.importKey(
      "spki",
      spkiFromCertificate(base64ToBytes(TEST_ROOT_DER)),
      { name: "ECDSA", namedCurve: "P-384" },
      false,
      ["verify"],
    )
    expect(await signedBy(base64ToBytes(TEST_LEAF_DER), issuer)).toBe(true)
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
