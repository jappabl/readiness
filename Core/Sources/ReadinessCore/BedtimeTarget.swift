import Foundation

/// What tonight has to be, said while there is still time to do something about it.
///
/// Every other message describes data already fixed: a morning verdict is about a night
/// that cannot be changed. This one is the exception, which is why it is worth the
/// interruption on the nights it fires.
public enum BedtimeTarget {

    /// How far above their own baseline tonight has to be before it is worth saying.
    /// Below this the widget carries it.
    public static let unusualMarginHours = 0.75

    /// How long before the usual bedtime the message may go out.
    public static let windowMinutes = 90.0

    /// Whether now is inside the window before tonight's usual bedtime.
    ///
    /// Bounded on both sides: a target delivered after bedtime is a reproach rather than
    /// a plan, and one delivered at teatime will have been forgotten.
    public static func isDue(now: Date, usualBedtime: Date) -> Bool {
        let secondsUntil = usualBedtime.timeIntervalSince(now)
        return secondsUntil > 0 && secondsUntil <= windowMinutes * 60
    }

    /// The sentence to send, or nil when tonight is an ordinary night.
    ///
    /// The debt arrives separately because it is no longer part of the need. It used to
    /// be folded in and repaid a fraction at a time; it is now its own decaying balance,
    /// so only yesterday's strain can lift tonight's target above the baseline. The
    /// balance is still the better reason to name when there is more of it than there is
    /// strain, which is what somebody four hours down actually needs to hear.
    public static func sentence(need: SleepNeed, debtHours: Double = 0) -> String? {
        guard need.hours - need.baseline >= unusualMarginHours else { return nil }
        let hours = need.hours.formatted(.number.precision(.fractionLength(0...1)))
        // Whichever of the two actually drove it. Naming the smaller one would be the
        // app explaining itself with the wrong reason.
        let because = need.strainAdjustment >= debtHours
            ? "Yesterday was hard."
            : "You are behind on sleep."
        return "🌙 \(because) Tonight needs about \(hours) hours."
    }
}
