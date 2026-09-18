import Foundation

/// The only health information that ever leaves the device.
///
/// Derived aggregates only — never raw samples, never a timeseries of measurements.
/// Kept small on purpose: a compact summary is both the privacy boundary and the thing
/// that decides whether a flat-priced coach is affordable.
public struct CoachContext: Codable, Equatable, Sendable {

    public struct MetricSummary: Codable, Equatable, Sendable {
        public let name: String
        public let value: Double
        public let baseline: Double
        public let z: Double
        public let unit: String
    }

    public struct DaySummary: Codable, Equatable, Sendable {
        public let day: String
        public let state: String
        public let composite: Double
        public let volume: Double
    }

    public struct ExerciseSummary: Codable, Equatable, Sendable {
        public let name: String
        public let muscle: String
        public let sets: Int
        public let reps: Int
        public let weight: Double
        public let rir: Int
    }

    public let today: String
    public let state: String
    public let composite: Double
    public let confidence: String
    public let daysOfHistory: Int
    public let gate: String?
    public let metrics: [MetricSummary]
    public let checkIn: [String: Int]?
    public let acwr: Double?
    public let recentDays: [DaySummary]
    public let program: [ExerciseSummary]
    public let proposedAdjustments: [String]
    public let uncertainty: [String]
    public let goal: String?
    public let limitations: String?

    public static let maximumRecentDays = 14

    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public var approximateBytes: Int { json.utf8.count }
}

public enum CoachContextBuilder {

    /// Rounds everything on the way out. Full float precision costs tokens and implies
    /// a certainty the measurements do not have.
    static func round(_ value: Double, places: Int = 2) -> Double {
        let factor = pow(10.0, Double(places))
        return (value * factor).rounded() / factor
    }

    public static func build(today: Date,
                             readiness: ReadinessResult,
                             readings: [MetricReading],
                             daysOfHistory: Int,
                             recommendation: Recommendation,
                             checkIn: CheckIn?,
                             acwr: Double?,
                             recentDays: [CoachContext.DaySummary],
                             program: [CoachContext.ExerciseSummary],
                             goal: String?,
                             limitations: String?,
                             describe: (SessionAdjustment) -> String) -> CoachContext {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        return CoachContext(
            today: formatter.string(from: today),
            state: recommendation.state.rawValue,
            composite: round(readiness.composite),
            confidence: readiness.confidence.rawValue,
            daysOfHistory: daysOfHistory,
            gate: readiness.gateApplied?.rawValue,
            metrics: readings.map {
                CoachContext.MetricSummary(name: $0.kind.rawValue,
                                           value: round($0.value, places: 1),
                                           baseline: round($0.baseline, places: 1),
                                           z: round($0.zScore),
                                           unit: $0.kind.unit)
            },
            checkIn: checkIn.map {
                ["soreness": $0.soreness, "energy": $0.energy,
                 "stress": $0.stress, "mood": $0.mood]
            },
            acwr: acwr.map { round($0) },
            recentDays: Array(recentDays.suffix(CoachContext.maximumRecentDays)),
            program: program,
            proposedAdjustments: recommendation.adjustments.map(describe),
            uncertainty: recommendation.uncertainty,
            goal: goal?.isEmpty == false ? goal : nil,
            limitations: limitations?.isEmpty == false ? limitations : nil)
    }
}
