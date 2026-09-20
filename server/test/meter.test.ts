import { describe, expect, test } from "vitest"
import { BURST_CAPACITY, FREE_MESSAGES, freshBucket, meterDecision, type MeterState } from "../src/limits"

const NOW = 1_700_000_000_000
const fresh = (): MeterState => ({ bucket: freshBucket(), freeUsed: 0 })

describe("the two meters applied together", () => {
  test("a free user gets exactly the free messages", () => {
    let state = fresh()
    for (let i = 0; i < FREE_MESSAGES; i++) {
      const out = meterDecision(state, false, NOW)
      expect(out.allowed).toBe(true)
      state = out.state
    }
    expect(meterDecision(state, false, NOW)).toMatchObject({ allowed: false, status: 402 })
  })

  test("the count only advances when the request is actually allowed", () => {
    // This is what the KV read-then-write got wrong: the increment has to be part of
    // the same decision that permitted it.
    const state: MeterState = { bucket: freshBucket(), freeUsed: FREE_MESSAGES }
    const out = meterDecision(state, false, NOW)
    expect(out.allowed).toBe(false)
    expect(out.state.freeUsed).toBe(FREE_MESSAGES)
  })

  test("a subscriber never touches the free counter", () => {
    const out = meterDecision({ bucket: freshBucket(), freeUsed: 99 }, true, NOW)
    expect(out.allowed).toBe(true)
    expect(out.state.freeUsed).toBe(99)
  })

  test("burst applies to subscribers too, because unlimited is not per second", () => {
    let state: MeterState = fresh()
    for (let i = 0; i < BURST_CAPACITY; i++) state = meterDecision(state, true, NOW).state
    expect(meterDecision(state, true, NOW)).toMatchObject({ allowed: false, status: 429 })
  })

  test("burst is checked before the free tier, so a rejected burst costs no message", () => {
    const empty: MeterState = { bucket: { tokens: 0, updated: NOW }, freeUsed: 0 }
    const out = meterDecision(empty, false, NOW)
    expect(out.status).toBe(429)
    expect(out.state.freeUsed).toBe(0)
  })

  test("a refused free request still spends its burst token", () => {
    const state: MeterState = { bucket: freshBucket(), freeUsed: FREE_MESSAGES }
    const out = meterDecision(state, false, NOW)
    expect(out.status).toBe(402)
    expect(out.state.bucket.tokens).toBeCloseTo(BURST_CAPACITY - 1, 6)
  })
})
