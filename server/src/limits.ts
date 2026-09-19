/**
 * The meter, moved off the device.
 *
 * `BurstLimiter` and `Paywall` already exist in Swift, in Core, with tests. They stay
 * there because the client still needs to show a countdown and a "one at a time"
 * message without a round trip. But a limit the client enforces is a courtesy: the
 * numbers below are the ones that actually decide, and they are a deliberate port
 * rather than a fresh invention, so the two never drift into telling the user
 * different things.
 *
 * Ported from Core/Sources/ReadinessCore/BurstLimiter.swift and Paywall.swift.
 */

/** How many can go out back to back. Comfortably more than anyone types by hand. */
export const BURST_CAPACITY = 8
/** Seconds to earn one back, which works out at five a minute sustained. */
export const REFILL_INTERVAL_SECONDS = 12
/** Enough answers to find out whether Jett is any good. */
export const FREE_MESSAGES = 5

export interface BucketState {
  tokens: number
  /** Epoch milliseconds, or null before the first request. */
  updated: number | null
}

export interface BucketDecision {
  allowed: boolean
  state: BucketState
  /** Seconds until the next one would go through. Null when it already did. */
  retryAfter: number | null
}

export function freshBucket(): BucketState {
  return { tokens: BURST_CAPACITY, updated: null }
}

export function consume(state: BucketState, nowMs: number): BucketDecision {
  let tokens = state.tokens

  if (state.updated !== null) {
    // Clocks move, including backwards. Treating a negative interval as elapsed time
    // would let anyone refill the bucket by changing the date. The client clamps this
    // too; here it is the one that counts, because here the clock is ours.
    const elapsed = Math.max(0, (nowMs - state.updated) / 1000)
    tokens = Math.min(BURST_CAPACITY, tokens + elapsed / REFILL_INTERVAL_SECONDS)
  }

  if (tokens < 1) {
    const wait = (1 - tokens) * REFILL_INTERVAL_SECONDS
    return {
      allowed: false,
      state: { tokens, updated: nowMs },
      retryAfter: Math.max(1, Math.ceil(wait)),
    }
  }
  return { allowed: true, state: { tokens: tokens - 1, updated: nowMs }, retryAfter: null }
}

export interface Allowance {
  allowed: boolean
  /** Null for a subscriber, who should never see a countdown. */
  remaining: number | null
}

export function allowance(used: number, isSubscriber: boolean): Allowance {
  if (isSubscriber) return { allowed: true, remaining: null }
  const left = Math.max(0, FREE_MESSAGES - Math.max(0, used))
  return { allowed: left > 0, remaining: left }
}
