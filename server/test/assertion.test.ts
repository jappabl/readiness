import { createHash } from "node:crypto"
import { describe, expect, test } from "vitest"
import { assertionMessage } from "../src/attest"

// The same inputs and the same two fingerprints are pinned in the app's tests
// (AssertionMessageTests.swift). If either side changes how it builds the message,
// its own test fails before the two can drift apart in production.
const CHALLENGE = "1700000000000.3f2c9a1e-0000-4000-8000-000000000000.c2lnbmF0dXJl"
const BODY = new TextEncoder().encode('{"messages":[]}')
const PURCHASE = "eyJhbGciOiJFUzI1NiJ9.eyJ0cmFuc2FjdGlvbklkIjoiMSJ9.c2ln"
const digest = (bytes: Uint8Array) => createHash("sha256").update(bytes).digest("hex")

describe("what a request's signature covers", () => {
  // Unchanged from before, so a build that has never bought anything keeps working.
  test("without a purchase, the challenge and then the body", async () => {
    const message = await assertionMessage(CHALLENGE, BODY, null)
    expect(digest(message)).toBe("6660619ef472a1f49abdf3767d9beafd6f2f5e2ad70f4c13d14456fdb542a9d5")
  })

  // The purchase travels in a header, and a header nobody signed can be swapped by
  // anyone who can see their own traffic: one subscriber's proof, everybody's Pro.
  test("with a purchase, its fingerprint as well", async () => {
    const message = await assertionMessage(CHALLENGE, BODY, PURCHASE)
    expect(message.length).toBe(CHALLENGE.length + BODY.length + 32)
    expect(digest(message)).toBe("1491dc1161f5adcd2f7fe4a2bb0f2174ef1e02e11467097b11fd415a4877f16a")
  })

  test("a different purchase is a different message", async () => {
    const one = await assertionMessage(CHALLENGE, BODY, PURCHASE)
    const other = await assertionMessage(CHALLENGE, BODY, PURCHASE + "x")
    expect(digest(one)).not.toBe(digest(other))
  })

  test("an empty header counts as no purchase", async () => {
    expect(digest(await assertionMessage(CHALLENGE, BODY, ""))).toBe(digest(await assertionMessage(CHALLENGE, BODY, null)))
  })
})
