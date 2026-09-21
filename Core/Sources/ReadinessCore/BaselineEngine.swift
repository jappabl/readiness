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

    /// How much of a day's weight the day before it keeps, in the trend.
    ///
    /// Derived, not tuned. `trendDays` was a flat average of the last seven *readings*,
    /// and a flat seven-day average has a mean data age of exactly 3 days and rests on
    /// exactly 7 readings. An exponential with retention r has mean age r/(1-r) and an
    /// effective sample size of (1+r)/(1-r); at 0.75 those are 3 and 7 exactly. So this is
    /// the same estimator by those two measures, moved onto a calendar axis. Not the same
    /// *numbers*: even on a perfect record it moves a score by about 2 points on average,
    /// and changes a band on 2.3% of mornings. Measured against noise-free physiology that
    /// movement is an improvement, and the gap it closes is much larger, but "identical"
    /// would be wrong, and the next reader would use it as an invariant.
    ///
    /// The problem being: `suffix(7)` of a list whose missing days have been compacted out
    /// is seven readings, not seven days. At four nights of wear a week it spans twelve
    /// days, and after a trip seventeen, so a dip that had recovered a fortnight ago was
    /// still holding the ring down, by up to eighteen points.
    ///
    /// (`SleepDebt.retention` is 0.85 rather than this, deliberately: a balance is an
    /// accumulator, not an average, so what has to match is where it settles: 6.67 times
    /// a nightly shortfall against the old window's 7. Same idea, different anchor.)
    public static let trendRetention = 0.75

    /// Below this share of the mean, a window's spread is arithmetic residue rather
    /// than variation. A byte-identical history of a value that cannot be represented
    /// exactly leaves about 1e-16 in both the mean and the deviation, and dividing one
    /// by the other gave a confident z of exactly 1.0 out of nothing at all.
    static let relativeSpreadFloor = 1e-9

    /// `daily` is one entry per calendar day, oldest first, nil where nothing was
    /// recorded. The nils are what make a week a week.
    public static func evaluate(daily: [Double?]) -> BaselineResult? {
        let clean: [Double?] = daily.map { value in
            guard let value, value.isFinite else { return nil }
            return value
        }
        guard let todayIndex = clean.lastIndex(where: { $0 != nil }),
              let today = clean[todayIndex] else { return nil }

        // The baseline window is calendar days too, sliced before the gaps are dropped.
        let earliest = Swift.max(0, todayIndex - windowDays)
        let window = clean[earliest..<todayIndex].compactMap { $0 }
        guard !window.isEmpty else { return nil }

        let mean = window.reduce(0, +) / Double(window.count)
        let variance = window.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(window.count)
        let sd = variance.squareRoot()

        // Each day back keeps `trendRetention` of the weight of the day after it. The
        // weight of the days that recorded nothing goes to the baseline mean, not to the
        // days that did.
        //
        // Renormalising over the recorded days was the obvious thing and it was wrong: it
        // hands whatever survives the gap the whole of the missing weight. After a week
        // off, today's reading carried 65% of its own "seven-day trend" and after a
        // fortnight 93%, so one night back read -1.64, past the clamp, and put the ring at
        // 32 red where the old estimator said 46.9. The trend exists precisely to stop one
        // night doing that. Measured against noise-free truth this is better at every wear
        // pattern and identical at full wear, where there is no missing weight to place.
        let fullWeight = 1 / (1 - trendRetention)
        var weighted = 0.0
        var weights = 0.0
        for index in stride(from: todayIndex, through: 0, by: -1) {
            guard let value = clean[index] else { continue }
            let weight = pow(trendRetention, Double(todayIndex - index))
            weighted += value * weight
            weights += weight
        }
        let trend = (weighted + (fullWeight - weights) * mean) / fullWeight

        let meaningful = sd > Swift.max(abs(mean) * relativeSpreadFloor, .leastNormalMagnitude)
        return BaselineResult(mean: mean, sd: sd, sampleCount: window.count,
                              zScore: meaningful ? (today - mean) / sd : 0,
                              trendZScore: meaningful ? (trend - mean) / sd : 0)
    }

    /// `series` is daily values, oldest first, with today's value last, and every entry a
    /// day that recorded something. Callers holding a dense record with gaps in it want
    /// `evaluate(daily:)` instead.
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

    /// `daily` is one entry per calendar day, oldest first, nil where nothing was
    /// recorded: the same shape `evaluate(daily:)` takes, so a caller cannot accidentally
    /// get the reading-count windows back by reaching for the convenience.
    public static func reading(kind: MetricKind, daily: [Double?]) -> MetricReading? {
        guard let today = daily.compactMap({ $0 }).last(where: { $0.isFinite }),
              let result = evaluate(daily: daily) else { return nil }
        return MetricReading(kind: kind, value: today, baseline: result.mean,
                             zScore: result.zScore,
                             scoringZ: kind.scoresOnTrend ? result.trendZScore : result.zScore,
                             scoringValue: kind.scoresOnTrend
                                 ? result.mean + result.trendZScore * result.sd : today,
                             sampleCount: result.sampleCount)
    }
}
