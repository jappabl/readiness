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
    ///
    /// Not `SignalScore.summary` on its own, which is written for a screen. In the app
    /// that sentence sits under a large labelled number, so "pulled it down most" has an
    /// obvious antecedent. On a lock screen there is nothing for "it" to refer to, and
    /// the reader is left asking pulled *what* down. So the signal and its number are
    /// stated first, and `summary` then explains them.
    public static func sentence(recovery: SignalScore, sleep: SignalScore,
                                recentSleepScores: [Double]) -> String? {
        if let bad = worstNews(recovery: recovery, sleep: sleep) {
            return [marker(for: bad.kind), heading(for: bad), bad.summary]
                .compactMap { $0 }
                .joined(separator: " ")
        }
        return bestNight(sleep: sleep, recent: recentSleepScores)
    }

    /// One glyph, leading, as a category marker rather than decoration.
    ///
    /// A lock screen is read in a glance and sorted before it is read at all. The glyph
    /// says which of three things this is faster than any word can, which is the one job
    /// worth giving it. It never appears mid-sentence and never stands in for a word.
    static func marker(for kind: SignalKind) -> String {
        switch kind {
        case .recovery: return "\u{1F50B}"
        case .sleep: return "\u{1F634}"
        case .strain: return "\u{1F525}"
        }
    }

    /// "Recovery 41." The antecedent the rest of the sentence needs.
    private static func heading(for score: SignalScore) -> String? {
        guard let value = score.value else { return nil }
        let name: String
        switch score.kind {
        case .recovery: name = "Recovery"
        case .sleep: name = "Sleep"
        case .strain: name = "Strain"
        }
        return "\(name) \(Int(value.rounded()))."
    }

    /// Whichever signal moved furthest down, provided it moved far enough to interrupt.
    ///
    /// Both are read, not just recovery: the night that felt fine and had almost no deep
    /// sleep shows up in the sleep score while HRV stays perfectly clean, and that is
    /// exactly the morning worth catching.
    private static func worstNews(recovery: SignalScore, sleep: SignalScore) -> SignalScore? {
        [recovery, sleep]
            // `.buildingBaseline` excluded alongside `.unavailable`: it is the coverage
            // the app's own UI labels "Still learning your normal"
            // (`InsightsView.coverageTitle`), a caveat a lock screen cannot carry. A
            // confident interruption off a number the screen itself hedges on would be
            // the app contradicting itself between channels.
            .filter { $0.coverage != .unavailable && $0.coverage != .buildingBaseline }
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
        return "\u{2728} Your best night in \(weeks(window.count)) weeks."
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
