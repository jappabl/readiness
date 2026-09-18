import Foundation

/// One meaningful relationship, or nothing. A feed of generic observations is worse than
/// silence, because it teaches the user to stop reading.
public enum InsightEngine {

    public struct TrainingDay: Equatable, Sendable {
        public let sleepHours: Double
        public let volumeLoad: Double
        public let isLowerBody: Bool

        public init(sleepHours: Double, volumeLoad: Double, isLowerBody: Bool) {
            self.sleepHours = sleepHours
            self.volumeLoad = volumeLoad
            self.isLowerBody = isLowerBody
        }
    }

    /// Sessions needed before any claim is worth making.
    public static let minimumSessions = 6
    /// How much better the good-sleep group must be before this counts as a pattern.
    public static let minimumLift = 0.10

    public static func sleepPerformancePattern(_ days: [TrainingDay]) -> String? {
        guard days.count >= minimumSessions else { return nil }

        let sorted = days.sorted { $0.sleepHours < $1.sleepHours }
        let midpoint = sorted.count / 2
        let shortNights = Array(sorted.prefix(midpoint))
        let longNights = Array(sorted.suffix(sorted.count - midpoint))
        guard !shortNights.isEmpty, !longNights.isEmpty else { return nil }

        // If every night is the same length there is no split to reason about.
        guard let threshold = longNights.first?.sleepHours,
              let shortest = longNights.map(\.sleepHours).min(),
              let longestShort = shortNights.map(\.sleepHours).max(),
              shortest > longestShort else { return nil }

        let poorMean = mean(shortNights.map(\.volumeLoad))
        let goodMean = mean(longNights.map(\.volumeLoad))
        guard poorMean > 0 else { return nil }

        let lift = (goodMean - poorMean) / poorMean
        guard lift >= minimumLift else { return nil }

        let percent = Int((lift * 100).rounded())
        let hours = (threshold * 2).rounded() / 2
        return "Your training volume has been about \(percent)% higher after nights of "
             + "\(hours.formatted(.number.precision(.fractionLength(0...1)))) hours of sleep or more."
    }

    private static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
}
