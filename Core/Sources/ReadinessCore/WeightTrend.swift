import Foundation

/// Whether the number is moving, which is the only question somebody weighing
/// themselves is actually asking.
///
/// The card showed today's figure and a sparkline, and the sparkline only appeared once
/// there were two readings, so a tester with one weigh-in saw a number with no context
/// and wrote that there was no way to tell whether he was losing anything.
///
/// Deliberately not a rate, a projection or a goal. Scales move a kilo on salt and a
/// full bladder, so this reports what changed between two readings and how far apart
/// they were, and lets the person do the arithmetic that only they have the context for.
public enum WeightTrend {

    public struct Reading: Sendable, Equatable {
        public let date: Date
        public let kilograms: Double
        public init(date: Date, kilograms: Double) {
            self.date = date
            self.kilograms = kilograms
        }
    }

    public struct Change: Sendable, Equatable {
        /// Signed, in kilograms. Negative is down.
        public let kilograms: Double
        public let from: Date
        public let to: Date
        public var days: Int {
            max(1, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: from),
                                                   to: Calendar.current.startOfDay(for: to)).day ?? 1)
        }
        public var isDown: Bool { kilograms < 0 }
    }

    /// The most recent reading, and the one before it.
    ///
    /// "Before it" means a different day, not a different entry. Two weigh-ins on the
    /// same morning are one morning's answer, and reporting "down 0.3 since today" is
    /// noise dressed as information.
    public static func latestChange(in readings: [Reading],
                                    calendar: Calendar = .current) -> Change? {
        let sorted = readings.sorted { $0.date < $1.date }
        guard let latest = sorted.last else { return nil }
        guard let previous = sorted.last(where: {
            !calendar.isDate($0.date, inSameDayAs: latest.date)
        }) else { return nil }
        return Change(kilograms: latest.kilograms - previous.kilograms,
                      from: previous.date, to: latest.date)
    }

    /// One reading per day, the last one of each, oldest first.
    ///
    /// A chart with three points stacked on one morning draws a vertical line and reads
    /// as a crash. The last weigh-in of a day is the one somebody settled on.
    public static func daily(_ readings: [Reading], calendar: Calendar = .current) -> [Reading] {
        var byDay: [Date: Reading] = [:]
        for reading in readings.sorted(by: { $0.date < $1.date }) {
            byDay[calendar.startOfDay(for: reading.date)] = reading
        }
        return byDay.values.sorted { $0.date < $1.date }
    }

    /// The readings inside a window ending at the most recent one, oldest first.
    ///
    /// Anchored to the last weigh-in rather than to today, so somebody who stopped
    /// weighing themselves a fortnight ago still sees the shape of what they recorded
    /// instead of an empty chart.
    public static func window(_ readings: [Reading], days: Int,
                              calendar: Calendar = .current) -> [Reading] {
        let daily = daily(readings, calendar: calendar)
        guard let end = daily.last?.date,
              let start = calendar.date(byAdding: .day, value: -(days - 1),
                                        to: calendar.startOfDay(for: end)) else { return daily }
        return daily.filter { $0.date >= start }
    }
}
