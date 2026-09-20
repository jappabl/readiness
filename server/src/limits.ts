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

/**
 * Both meters in one decision, so they can be applied inside a single transaction.
 *
 * The first version checked the burst bucket in a Durable Object and then did a
 * read-then-write of the free counter in KV. That second half was a race: two requests
 * arriving together both read the same count, both passed, and both wrote it back one
 * higher. KV is also eventually consistent, so the stale window is far wider than a
 * true race. An anti-abuse counter cannot be built out of a non-transactional get/put.
 */
export interface MeterState {
  bucket: BucketState
  freeUsed: number
}

export interface MeterOutcome {
  allowed: boolean
  /** 429 for burst, 402 for the free tier, undefined when allowed. */
  status?: number
  retryAfter?: number
  state: MeterState
}

export function meterDecision(
  state: MeterState,
  isSubscriber: boolean,
  nowMs: number,
): MeterOutcome {
  const burst = consume(state.bucket, nowMs)
  if (!burst.allowed) {
    return {
      allowed: false,
      status: 429,
      retryAfter: burst.retryAfter ?? REFILL_INTERVAL_SECONDS,
      state: { bucket: burst.state, freeUsed: state.freeUsed },
    }
  }

  if (isSubscriber) {
    return { allowed: true, state: { bucket: burst.state, freeUsed: state.freeUsed } }
  }

  const room = allowance(state.freeUsed, false)
  if (!room.allowed) {
    // The burst token is still spent. Someone hammering the endpoint after running out
    // of free messages should still be rate limited.
    return { allowed: false, status: 402, state: { bucket: burst.state, freeUsed: state.freeUsed } }
  }
  return { allowed: true, state: { bucket: burst.state, freeUsed: state.freeUsed + 1 } }
}
