import Foundation

/// A token bucket over the coach.
///
/// Paying buys unlimited use, not unlimited use per second. The bucket holds a burst
/// worth of messages and refills steadily, so a conversation never notices it and a
/// script pointed at the endpoint stops after a few seconds. There is no monthly cap
/// anywhere, and this never refuses somebody twice for the same reason: waiting always
/// earns the next message back.
public enum BurstLimiter {

    /// How many can go out back to back. Comfortably more than anyone types by hand.
    public static let capacity = 8

    /// Seconds to earn one back, which works out at five a minute sustained.
    public static let refillInterval: TimeInterval = 12

    public struct State: Equatable, Sendable, Codable {
        var tokens: Double
        var updated: Date?

        public init() {
            tokens = Double(BurstLimiter.capacity)
            updated = nil
        }

        public init(tokens: Double, updated: Date?) {
            self.tokens = tokens
            self.updated = updated
        }
    }

    public struct Decision: Equatable, Sendable {
        public let allowed: Bool
        public let state: State
        /// Seconds until the next one would go through. Nil when it already did.
        public let retryAfter: TimeInterval?
    }

    public static func consume(_ state: State, now: Date) -> Decision {
        var tokens = state.tokens

        if let updated = state.updated {
            // Device clocks move, including backwards. Treating a negative interval as
            // elapsed time would let anyone refill the bucket by changing the date.
            let elapsed = max(0, now.timeIntervalSince(updated))
            tokens = min(Double(capacity), tokens + elapsed / refillInterval)
        }

        guard tokens >= 1 else {
            let wait = (1 - tokens) * refillInterval
            return Decision(allowed: false,
                            state: State(tokens: tokens, updated: now),
                            retryAfter: max(1, wait.rounded(.up)))
        }
        return Decision(allowed: true,
                        state: State(tokens: tokens - 1, updated: now),
                        retryAfter: nil)
    }
}
