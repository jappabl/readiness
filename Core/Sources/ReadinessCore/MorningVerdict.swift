import Foundation

/// Whether this morning is worth a lock screen, and what it says if it is.
///
/// The app's core output, so it is never budgeted and never suppressed for repeating
/// itself. What produces silence is the morning having nothing to report.
public enum MorningVerdict {

    /// How far a contributor must have moved a score before interrupting for it.
    ///
    /// `SignalScore.notableMagnitude` (2.0) is the bar for text sitting next to the
    /// number, where the reader has already chosen to look. A lock screen costs more.
    public static let notableForInterruption = 5.0

    /// Nights of history needed before "a best" is a claim rather than an accident.
    public static let minimumHistoryForBest = 14

    /// How far back a best has to reach.
    public static let bestWindow = 21

    /// The sentence to send, or nil when this morning is not worth interrupting for.
    public static func sentence(recovery: SignalScore, sleep: SignalScore,
                                recentSleepScores: [Double]) -> String? {
        if let bad = worstNews(recovery: recovery, sleep: sleep) { return bad.summary }
        return bestNight(sleep: sleep, recent: recentSleepScores)
    }

    /// Whichever signal moved furthest down, provided it moved far enough to interrupt.
    ///
    /// Both are read, not just recovery: the night that felt fine and had almost no deep
    /// sleep shows up in the sleep score while HRV stays perfectly clean, and that is
    /// exactly the morning worth catching.
    private static func worstNews(recovery: SignalScore, sleep: SignalScore) -> SignalScore? {
        [recovery, sleep]
            .filter { $0.coverage != .unavailable }
            .filter { ($0.contributors.first?.magnitude ?? 0) <= -notableForInterruption }
            .min { ($0.contributors.first?.magnitude ?? 0) < ($1.contributors.first?.magnitude ?? 0) }
    }

    /// A night better than every one it can be compared against.
    ///
    /// Ordinary good nights are the widget's job. This fires only for something the user
    /// would want to be told, which by construction is rare.
    private static func bestNight(sleep: SignalScore, recent: [Double]) -> String? {
        guard sleep.coverage != .unavailable, let value = sleep.value else { return nil }
        let window = Array(recent.suffix(bestWindow))
        guard window.count >= minimumHistoryForBest,
              let best = window.max(), value > best else { return nil }
        return "Your best night in \(weeks(window.count)) weeks."
    }

    /// Named for what it actually beat. Claiming three weeks off fourteen nights is a
    /// small lie, and the one place the app cannot afford small lies is the lock screen.
    private static func weeks(_ nights: Int) -> String {
        switch nights / 7 {
        case ..<3: return "two"
        default: return "three"
        }
    }
}
