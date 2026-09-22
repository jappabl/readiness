import { describe, expect, test } from "vitest"
import { challengeIsValid, issueChallenge, type Env } from "../src/index"

const BUNDLE = "com.coachjett.ios"
const SECRET = "a-real-secret-nobody-can-read-off-the-app-store"

function env(overrides: Partial<Env> = {}): Env {
  return { BUNDLE_ID: BUNDLE, CHALLENGE_SECRET: SECRET, ...overrides } as Env
}

describe("the challenge that stops an attestation being replayed", () => {
  test("one we issued validates", async () => {
    const e = env()
    expect(await challengeIsValid(await issueChallenge(e), e, Date.now())).toBe(true)
  })

  test("a tampered signature does not", async () => {
    const e = env()
    const [issued, nonce] = (await issueChallenge(e)).split(".")
    expect(await challengeIsValid(`${issued}.${nonce}.forged`, e, Date.now())).toBe(false)
  })

  test("one older than five minutes does not", async () => {
    const e = env()
    const challenge = await issueChallenge(e)
    expect(await challengeIsValid(challenge, e, Date.now() + 6 * 60 * 1000)).toBe(false)
  })

  // The bundle id is printed in the app's own Info.plist and sits in the App Store URL.
  // If it can sign a challenge, anybody can mint one, and the replay defence is a
  // formality. This is the test that would have caught the fallback.
  test("the bundle id cannot sign one", async () => {
    const forged = await issueChallenge(env({ CHALLENGE_SECRET: BUNDLE }))
    expect(await challengeIsValid(forged, env(), Date.now())).toBe(false)
  })

  // Fail closed. A missing secret must stop the door working, never quietly pick a
  // weaker key, because the second one looks healthy from the outside.
  test("no secret issues nothing", async () => {
    await expect(issueChallenge(env({ CHALLENGE_SECRET: undefined }))).rejects.toThrow()
  })

  test("no secret validates nothing, including a well-formed challenge", async () => {
    const real = await issueChallenge(env())
    expect(await challengeIsValid(real, env({ CHALLENGE_SECRET: undefined }), Date.now())).toBe(false)
  })
})
