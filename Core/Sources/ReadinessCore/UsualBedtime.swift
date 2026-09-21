import Foundation

/// When this person usually goes to bed, expressed as a moment tonight.
///
/// The bedtime message is the only thing the app says before the thing it is about, so
/// unlike every other decision it needs a time to aim at rather than a reading to judge.
///
/// Bedtimes are a clock and not a number, which is the whole difficulty. As minutes past
/// midnight, 23:40 is 1420 and 00:20 is 20, and their mean is 720: midday. Everything
/// here works in a frame that puts the wrap somewhere nobody sleeps.
public enum UsualBedtime {

    /// Below this there is no habit to aim at, only a handful of nights.
    public static let minimumNights = 7

    /// How far back to look. A bedtime that moved a month ago is not this person's now.
    public static let windowNights = 28

    /// The hour the day is cut at, for the purpose of deciding what counts as a bedtime.
    ///
    /// Two in the afternoon, because it has to fall in the gap everybody is awake. Cut
    /// at midnight and a 00:30 sleeper's nights land on both sides of it.
    static let dayBreakHour = 14

    /// Tonight's target, or nil when there are not enough nights to know.
    ///
    /// - Parameter bedtimes: when the primary sleep began, on any night, in any order.
    public static func tonight(from bedtimes: [Date], now: Date,
                               calendar: Calendar = .current) -> Date? {
        guard let cutoff = calendar.date(byAdding: .day, value: -windowNights, to: now) else {
            return nil
        }
        let recent = bedtimes.filter { $0 >= cutoff && $0 <= now }
        guard recent.count >= minimumNights else { return nil }

        // Minutes since the afternoon break, so an evening and the small hours after it
        // are adjacent numbers rather than opposite ends of the range.
        let offsets = recent.map { minutesSinceBreak($0, calendar: calendar) }.sorted()
        let middle = offsets.count / 2
        let median = offsets.count.isMultiple(of: 2)
            ? (offsets[middle - 1] + offsets[middle]) / 2
            : offsets[middle]

        // Back onto a wall clock, then onto the break that tonight belongs to. A 22:30
        // habit lands this evening; a 01:15 habit lands after midnight, which is the
        // next calendar day and still tonight's bedtime.
        let breakToday = calendar.date(bySettingHour: dayBreakHour, minute: 0, second: 0,
                                       of: calendar.startOfDay(for: now))
        guard let breakToday else { return nil }
        let base = breakToday > now
            ? calendar.date(byAdding: .day, value: -1, to: breakToday) ?? breakToday
            : breakToday
        return base.addingTimeInterval(median * 60)
    }

    private static func minutesSinceBreak(_ date: Date, calendar: Calendar) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        let breakMinutes = Double(dayBreakHour * 60)
        return minutes >= breakMinutes ? minutes - breakMinutes : minutes + (1440 - breakMinutes)
    }
}
