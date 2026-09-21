import Foundation

/// Everything the decision needs to know about what has already been said.
///
/// The engine is a pure function, so it cannot look anything up. The app persists this
/// between launches and hands it back on the next decision.
///
/// Encodes compactly and tolerates unknown keys, but `budget` is a required key and
/// there is no version field, so the synthesized `Decodable` fails outright on an older
/// payload missing it. Every field added after v1 must be `Optional` (so its absence
/// decodes to `nil` rather than failing the whole record) or this type needs a custom
/// `init(from:)` that can supply a default. The app should decode with `try?`, falling
/// back to `NotificationRecord()` on failure, rather than letting a decode error crash
/// or wedge notifications entirely.
public struct NotificationRecord: Equatable, Sendable, Codable {

    public var lastMorningVerdict: Date?
    public var lastIllnessGate: Date?
    public var lastBedtimeTarget: Date?
    /// The exact words last sent, because insight novelty is a text comparison rather
    /// than a calendar one: a finding that has not changed is not news, however long ago
    /// it was first said.
    public var lastInsight: String?
    public var budget: NotificationBudget.State

    public init() {
        budget = NotificationBudget.State()
    }

    /// Whether this moment has already gone out on the day `now` falls in.
    ///
    /// Always false for `.newInsight`: that moment is bounded by its own words, not by
    /// the calendar, and a day-based block would be a second rule doing nothing.
    public func alreadySentToday(_ moment: NotificationMoment, now: Date,
                                 calendar: Calendar = .current) -> Bool {
        let last: Date?
        switch moment {
        case .morningVerdict: last = lastMorningVerdict
        case .illnessGate: last = lastIllnessGate
        case .bedtimeTarget: last = lastBedtimeTarget
        case .newInsight: return false
        }
        guard let last else { return false }
        return calendar.isDate(last, inSameDayAs: now)
    }
}
