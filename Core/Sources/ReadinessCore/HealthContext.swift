import Foundation

/// Dated, derived summaries for coaching. Input observations stay on the device.
public struct HealthContext: Codable, Equatable, Sendable {
    public struct Metric: Codable, Equatable, Sendable {
        public let name: String
        public let unit: String
        public let latest: Double
        public let recordedOn: String
        public let daysAgo: Int
        public let mean7Days: Double?
        public let days7: Int
        public let mean28Days: Double?
        public let days28: Int
    }

    public struct Observation: Sendable {
        public let date: Date
        public let value: Double
        public init(date: Date, value: Double) { self.date = date; self.value = value }
    }

    public struct Stream: Sendable {
        public let name: String
        public let unit: String
        public let observations: [Observation]
        public init(name: String, unit: String, observations: [Observation]) {
            self.name = name; self.unit = unit; self.observations = observations
        }
    }

    public let metrics: [Metric]
    public let sleepTargetHours: Double

    /// Only recorded days enter the means. Today is excluded because totals can still
    /// be accumulating. A missing day is not a zero and cannot improve a score.
    public static func build(streams: [Stream], today: Date, sleepTargetHours: Double = 8,
                             calendar: Calendar = .current) -> HealthContext {
        let end = calendar.startOfDay(for: today)
        let start7 = calendar.date(byAdding: .day, value: -7, to: end)!
        let start28 = calendar.date(byAdding: .day, value: -28, to: end)!
        let start180 = calendar.date(byAdding: .day, value: -179, to: end)!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let metrics = streams.compactMap { stream -> Metric? in
            let valid = stream.observations.filter {
                $0.value.isFinite && $0.value >= 0 && $0.date <= today
                    && calendar.startOfDay(for: $0.date) >= start180
            }.sorted { $0.date < $1.date }
            let days = Dictionary(valid.map { (calendar.startOfDay(for: $0.date), $0.value) },
                                  uniquingKeysWith: { _, newer in newer })
            guard let date = days.keys.max(), let latest = days[date] else { return nil }
            let week = days.filter { $0.key >= start7 && $0.key < end }.map(\.value)
            let month = days.filter { $0.key >= start28 && $0.key < end }.map(\.value)
            func mean(_ values: [Double]) -> Double? {
                values.isEmpty ? nil : CoachContextBuilder.round(values.reduce(0, +) / Double(values.count), places: 1)
            }
            return Metric(name: stream.name, unit: stream.unit,
                          latest: CoachContextBuilder.round(latest, places: 1),
                          recordedOn: formatter.string(from: date),
                          daysAgo: calendar.dateComponents([.day], from: date, to: end).day ?? 0,
                          mean7Days: mean(week), days7: week.count,
                          mean28Days: mean(month), days28: month.count)
        }
        return HealthContext(metrics: metrics, sleepTargetHours: sleepTargetHours)
    }

    public var brief: String {
        guard !metrics.isEmpty else { return "Health summaries: no records available." }
        var lines = ["Health summaries: latest value and local date; prior 7/28 calendar days mean [recorded days].",
                     "Today excluded from means; today's activity/intake totals may be incomplete. Missing is unknown.",
                     // Whatever the app is actually using. It used to say "is a default"
                     // because it was one; it is handed the learned need now, and calling
                     // that a default contradicted the rules two lines above in the same
                     // request. Rounded, because sixteen significant figures of sleep need
                     // is not a number anybody meant.
                     "Sleep need \(sleepTargetHours.formatted(.number.precision(.fractionLength(1))))h, learned from their own nights. Stages are device estimates."]
        for metric in metrics {
            var line = "\(metric.name): \(metric.latest)\(metric.unit) @\(metric.recordedOn)"
            if metric.daysAgo > 0 { line += " (\(metric.daysAgo)d ago)" }
            if let mean = metric.mean7Days { line += "; 7d \(mean) [\(metric.days7)/7]" }
            if let mean = metric.mean28Days { line += "; 28d \(mean) [\(metric.days28)/28]" }
            lines.append(line)
        }
        lines.append("Logged intake is not total intake; absence is not fasting, dehydration, or zero caffeine/alcohol.")
        lines.append("Daily caffeine/alcohol totals do not reveal timing. Mindful minutes do not measure stress.")
        return lines.joined(separator: "\n")
    }
}
