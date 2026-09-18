import Foundation

/// What a free user is allowed right now.
public struct CoachAllowance: Equatable, Sendable {
    public let isAllowed: Bool
    /// Nil for a subscriber, who should never see a countdown.
    public let remaining: Int?

    /// Whether to put the count in front of the user. Counting down from the first
    /// message is how a trial teaches somebody to resent the app before they have
    /// decided anything.
    public var showsRemaining: Bool {
        guard let remaining else { return false }
        return remaining <= Paywall.countdownAppearsAt
    }
}

/// Where the line sits.
///
/// The gate is on the coach, and only the coach. Everything the app measures stays
/// free: the readiness call, the rings, the health monitor, the evidence behind the
/// decision. Charging for a number the watch already recorded is charging for someone
/// else's work, and the coach is the one feature with a real cost per use.
public enum Paywall {

    /// Enough answers to find out whether Jett is any good. Three is a teaser; this is
    /// meant to be a genuine try.
    public static let freeMessages = 5

    /// The countdown stays out of sight until this many are left.
    public static let countdownAppearsAt = 2

    public static func allowance(used: Int, isSubscribed: Bool) -> CoachAllowance {
        guard !isSubscribed else { return CoachAllowance(isAllowed: true, remaining: nil) }
        let left = max(0, freeMessages - max(0, used))
        return CoachAllowance(isAllowed: left > 0, remaining: left)
    }
}
