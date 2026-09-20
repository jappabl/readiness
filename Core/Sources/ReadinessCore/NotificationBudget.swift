import Foundation

/// A token bucket over the messages Jett initiates.
///
/// The jar holds three coins and one drops in every two days. A day worth talking about
/// can spend two or three; doing that leaves him genuinely quiet for the next few days,
/// which is the behaviour wanted. Sustained, it settles around three or four a week.
///
/// A weekly cap was considered and rejected: it cannot distinguish four messages spread
/// across a week from four on Monday, and it resets on an arbitrary boundary, so someone
/// who spends the allowance by Saturday is mute until midnight Sunday and then has a full
/// allowance again. A bucket has no boundary — it just makes a busy day cost something.
///
/// This is `BurstLimiter`'s arithmetic with different constants, deliberately copied
/// rather than shared. `BurstLimiter` guards a paying user's conversation with the coach,
/// and no notification change should be able to reach it.
public enum NotificationBudget {

    /// How many budgeted messages can go out close together on one eventful day.
    public static let capacity = 3

    /// Seconds to earn one back. Two days, which sets the long-run average.
    public static let refillInterval: TimeInterval = 48 * 60 * 60

    public struct State: Equatable, Sendable, Codable {
        var tokens: Double
        var updated: Date?

        public init() {
            tokens = Double(NotificationBudget.capacity)
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
    }

    public static func consume(_ state: State, now: Date) -> Decision {
        var tokens = state.tokens

        if let updated = state.updated {
            // Device clocks move, including backwards. A forward jump refills the
            // bucket with or without this clamp, so that is not what it guards against.
            // Without it, a backwards correction would drive tokens deeply negative, and
            // a user with a full bucket who crosses one would be locked out of every
            // message until real time caught back up to the clock's old reading.
            let elapsed = max(0, now.timeIntervalSince(updated))
            tokens = min(Double(capacity), tokens + elapsed / refillInterval)
        }

        guard tokens >= 1 else {
            return Decision(allowed: false, state: State(tokens: tokens, updated: now))
        }
        return Decision(allowed: true, state: State(tokens: tokens - 1, updated: now))
    }
}
