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

    /// `series` is daily values, oldest first, with today's value last.
    public static func evaluate(series: [Double]) -> BaselineResult? {
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
        let z = sd > 0 ? (today - mean) / sd : 0
        let trendZ = sd > 0 ? (trend - mean) / sd : 0

        return BaselineResult(mean: mean, sd: sd, sampleCount: window.count,
                              zScore: z, trendZScore: trendZ)
    }

    public static func reading(kind: MetricKind, series: [Double]) -> MetricReading? {
        guard let today = series.last, let result = evaluate(series: series) else { return nil }
        return MetricReading(kind: kind, value: today, baseline: result.mean,
                             zScore: result.zScore, sampleCount: result.sampleCount)
    }
}
