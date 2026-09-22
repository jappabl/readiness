import Foundation

/// The one message this app sends about money.
///
/// A two week trial that ends in a silent charge is the most reliable way an app earns
/// a refund request and a one star review, and the person is right to be annoyed: they
/// agreed to try something, not to remember a date. Apple sends its own reminder, on its
/// own schedule, which we neither control nor see. This is ours, and it arrives early
/// enough to act on.
///
/// Pure, so the lead time and the sentence are settled by `swift test` rather than by
/// reading a notification on a phone two weeks from now.
public enum TrialReminder {

    /// How long before the charge the reminder lands.
    ///
    /// Two days rather than one: cancelling means finding Settings, and somebody who
    /// sees this at eleven at night should still have a whole day left to do it.
    public static let lead: TimeInterval = 2 * 24 * 60 * 60

    /// When to fire, or nil when there is nothing useful to say.
    public static func fireDate(trialEnds: Date, now: Date) -> Date? {
        let fire = trialEnds.addingTimeInterval(-lead)
        // A date in the past is delivered by iOS the instant it is scheduled, which
        // turns a warning into an announcement about a charge already on its way.
        guard fire > now else { return nil }
        return fire
    }

    /// Written for a lock screen, where it is the whole message and there is no app
    /// around it to explain anything.
    ///
    /// `priceLine` is the price and its period as the App Store itself renders them,
    /// which is the only form that is right in every country.
    public static func body(priceLine: String) -> String {
        let days = Int(lead / 86_400)
        return "Your free trial ends in \(days) days. Coach Jett is \(priceLine) after "
            + "that. You can cancel any time in Settings."
    }
}
