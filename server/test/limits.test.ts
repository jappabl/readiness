import { describe, expect, test } from "vitest"
import {
  BURST_CAPACITY, REFILL_INTERVAL_SECONDS, FREE_MESSAGES,
  freshBucket, consume, allowance,
} from "../src/limits"

const SECOND = 1000

describe("the burst bucket", () => {
  test("a full bucket lets a burst through and then stops", () => {
    let state = freshBucket()
    const now = 1_700_000_000_000
    for (let i = 0; i < BURST_CAPACITY; i++) {
      const decision = consume(state, now)
      expect(decision.allowed).toBe(true)
      state = decision.state
    }
    const refused = consume(state, now)
    expect(refused.allowed).toBe(false)
    expect(refused.retryAfter).toBe(REFILL_INTERVAL_SECONDS)
  })

  test("waiting always earns the next one back", () => {
    let state: ReturnType<typeof freshBucket> = { tokens: 0, updated: 1_000_000 }
    const refused = consume(state, 1_000_000)
    expect(refused.allowed).toBe(false)
    const later = consume(refused.state, 1_000_000 + REFILL_INTERVAL_SECONDS * SECOND)
    expect(later.allowed).toBe(true)
  })

  test("a clock moving backwards does not refill the bucket", () => {
    const state = { tokens: 0.5, updated: 2_000_000 }
    // An hour earlier than the last update. Negative elapsed must count as zero.
    const decision = consume(state, 2_000_000 - 3_600 * SECOND)
    expect(decision.allowed).toBe(false)
    expect(decision.state.tokens).toBeCloseTo(0.5, 6)
  })

  test("refill never exceeds capacity however long the wait", () => {
    const state = { tokens: 1, updated: 0 }
    const decision = consume(state, 10_000 * SECOND)
    expect(decision.state.tokens).toBeCloseTo(BURST_CAPACITY - 1, 6)
  })

  test("retryAfter is never less than a second", () => {
    const state = { tokens: 0.999, updated: 5_000 }
    const decision = consume(state, 5_000)
    expect(decision.retryAfter).toBe(1)
  })
})

describe("the free tier", () => {
  test("a subscriber has no count and never sees one", () => {
    expect(allowance(999, true)).toEqual({ allowed: true, remaining: null })
  })

  test("a free user gets exactly the free messages, then the paywall", () => {
    expect(allowance(0, false)).toEqual({ allowed: true, remaining: FREE_MESSAGES })
    expect(allowance(FREE_MESSAGES - 1, false)).toEqual({ allowed: true, remaining: 1 })
    expect(allowance(FREE_MESSAGES, false)).toEqual({ allowed: false, remaining: 0 })
  })

  test("a nonsense count cannot buy extra messages", () => {
    expect(allowance(-50, false).remaining).toBe(FREE_MESSAGES)
  })
})
