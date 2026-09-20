import Foundation

public struct BaselineResult: Sendable, Equatable {
    public let mean: Double
    public let sd: Double
    public let sampleCount: Int
    /// Today's value against the rolling baseline.
    public let zScore: Double
    /// The last week's average against the same baseline. This is what separates
    /// "one rough night" from "something is actually going on".
    public let trendZScore: Double
}

public enum BaselineEngine {
    public static let windowDays = 60
    public static let trendDays = 7

    /// Below this share of the mean, a window's spread is arithmetic residue rather
    /// than variation. A byte-identical history of a value that cannot be represented
    /// exactly leaves about 1e-16 in both the mean and the deviation, and dividing one
    /// by the other gave a confident z of exactly 1.0 out of nothing at all.
    static let relativeSpreadFloor = 1e-9

    /// `series` is daily values, oldest first, with today's value last.
    public static func evaluate(series: [Double]) -> BaselineResult? {
        // Non-finite values are dropped rather than carried. HealthKit should not
        // produce them, but one NaN anywhere in a window poisons the mean, the
        // deviation and every reading taken against them for the next sixty days.
        // And it reaches the screen as a tile reading "NaN ms".
        let series = series.filter(\.isFinite)
        guard let today = series.last else { return nil }

        let window = Array(series.dropLast().suffix(windowDays))
        guard !window.isEmpty else { return nil }

        let mean = window.reduce(0, +) / Double(window.count)
        let variance = window.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(window.count)
        let sd = variance.squareRoot()

        let trendSlice = series.suffix(trendDays)
        let trend = trendSlice.reduce(0, +) / Double(trendSlice.count)

        // A flat history carries no information about dispersion, so it cannot say
        // today is unusual. Zero, not infinity.
        let meaningful = sd > Swift.max(abs(mean) * relativeSpreadFloor, .leastNormalMagnitude)
        let z = meaningful ? (today - mean) / sd : 0
        let trendZ = meaningful ? (trend - mean) / sd : 0

        return BaselineResult(mean: mean, sd: sd, sampleCount: window.count,
                              zScore: z, trendZScore: trendZ)
    }

    public static func reading(kind: MetricKind, series: [Double]) -> MetricReading? {
        guard let today = series.last(where: { $0.isFinite }),
              let result = evaluate(series: series) else { return nil }
        return MetricReading(kind: kind, value: today, baseline: result.mean,
                             zScore: result.zScore,
                             scoringZ: kind.scoresOnTrend ? result.trendZScore : result.zScore,
                             sampleCount: result.sampleCount)
    }
}
