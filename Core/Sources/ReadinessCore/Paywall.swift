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
/// The gate is on the two things with a real cost per use: the coach, and meal photo
/// estimates. Everything the app measures stays free: the readiness call, the rings, the
/// health monitor, the evidence behind the decision. Charging for a number the watch
/// already recorded is charging for someone else's work. Typing a meal in stays free too;
/// only the photo reading costs anything.
public enum Paywall {

    /// Enough answers to find out whether Jett is any good. Three is a teaser; this is
    /// meant to be a genuine try.
    public static let freeMessages = 5

    /// Meal photo estimates before Pro. A taste, not a trial: enough to see it read a
    /// plate. The server counts the same number and has the final say.
    public static let freeMealPhotos = 3

    /// The countdown stays out of sight until this many are left.
    public static let countdownAppearsAt = 2

    public static func allowance(used: Int, isSubscribed: Bool) -> CoachAllowance {
        allowance(used: used, free: freeMessages, isSubscribed: isSubscribed)
    }

    public static func mealPhotoAllowance(used: Int, isSubscribed: Bool) -> CoachAllowance {
        allowance(used: used, free: freeMealPhotos, isSubscribed: isSubscribed)
    }

    private static func allowance(used: Int, free: Int, isSubscribed: Bool) -> CoachAllowance {
        guard !isSubscribed else { return CoachAllowance(isAllowed: true, remaining: nil) }
        let left = max(0, free - max(0, used))
        return CoachAllowance(isAllowed: left > 0, remaining: left)
    }
}
