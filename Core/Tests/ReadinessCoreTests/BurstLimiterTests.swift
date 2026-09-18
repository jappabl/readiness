import Testing
import Foundation
@testable import ReadinessCore

/// Paying buys unlimited use, not unlimited use *per second*. A conversation never
/// touches this; a script pointed at the endpoint hits it immediately.
@Suite("Burst limiting the coach")
struct BurstLimiterTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a full bucket lets a whole burst through")
    func burstIsAllowed() {
        var state = BurstLimiter.State()
        for i in 0..<BurstLimiter.capacity {
            let result = BurstLimiter.consume(state, now: start)
            #expect(result.allowed, "refused message \(i + 1) of a fresh burst")
            state = result.state
        }
    }

    @Test("one more in the same instant is refused, with a time to wait")
    func burstThenRefusal() {
        var state = BurstLimiter.State()
        for _ in 0..<BurstLimiter.capacity {
            state = BurstLimiter.consume(state, now: start).state
        }
        let result = BurstLimiter.consume(state, now: start)
        #expect(!result.allowed)
        #expect((result.retryAfter ?? 0) > 0, "a refusal with no wait tells the user nothing")
        #expect((result.retryAfter ?? 0) <= BurstLimiter.refillInterval)
    }

    @Test("waiting earns the next message back")
    func refillsOverTime() {
        var state = BurstLimiter.State()
        for _ in 0..<BurstLimiter.capacity {
            state = BurstLimiter.consume(state, now: start).state
        }
        #expect(!BurstLimiter.consume(state, now: start).allowed)
        let later = start.addingTimeInterval(BurstLimiter.refillInterval)
        #expect(BurstLimiter.consume(state, now: later).allowed)
    }

    @Test("idling for a week does not bank a week of messages")
    func refillIsCapped() {
        var state = BurstLimiter.State()
        state = BurstLimiter.consume(state, now: start).state
        let muchLater = start.addingTimeInterval(7 * 24 * 3600)

        var allowed = 0
        for _ in 0..<(BurstLimiter.capacity * 4) {
            let result = BurstLimiter.consume(state, now: muchLater)
            if result.allowed { allowed += 1 }
            state = result.state
        }
        #expect(allowed == BurstLimiter.capacity, "the bucket overflowed to \(allowed)")
    }

    @Test("a clock moved backwards does not hand out free messages")
    func clockGoingBackwardsIsSafe() {
        // Device clocks move. Treating a negative interval as elapsed time would let
        // anyone refill the bucket by changing the date.
        var state = BurstLimiter.State()
        for _ in 0..<BurstLimiter.capacity {
            state = BurstLimiter.consume(state, now: start).state
        }
        let earlier = start.addingTimeInterval(-86_400)
        #expect(!BurstLimiter.consume(state, now: earlier).allowed)
    }

    @Test("a steady conversation is never interrupted")
    func realConversationIsUnaffected() {
        // One message every twenty seconds for an hour: faster than anyone actually
        // types, and it must never be refused.
        var state = BurstLimiter.State()
        for step in 0..<180 {
            let now = start.addingTimeInterval(Double(step) * 20)
            let result = BurstLimiter.consume(state, now: now)
            #expect(result.allowed, "refused a normal message at \(step * 20)s")
            state = result.state
        }
    }

    @Test("the sustained rate is generous enough to be invisible")
    func sustainedRateIsSane() {
        let perMinute = 60 / BurstLimiter.refillInterval
        #expect(perMinute >= 3, "under three a minute would interrupt a real conversation")
    }
}
