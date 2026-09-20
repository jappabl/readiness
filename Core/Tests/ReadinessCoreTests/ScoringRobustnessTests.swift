import Testing
import Foundation
@testable import ReadinessCore

/// Two changes to how today is scored, and the reasons they are not arbitrary.
///
/// Single-night HRV is the noisiest input the app has, and the athlete-monitoring
/// literature is fairly consistent that a rolling average carries the signal while one
/// night mostly carries noise. And the original weights came from the spec rather than
/// from anything measured here, with the noisiest input given the largest share of the
/// decision.
@Suite("How today is weighted")
struct ScoringRobustnessTests {

    @Test("HRV is scored on its trend, not on one night")
    func hrvScoresOnTrend() {
        #expect(MetricKind.hrv.scoresOnTrend)
    }

    @Test("the steady metrics are still scored on today")
    func othersScoreOnToday() {
        for kind in MetricKind.allCases where kind != .hrv {
            #expect(!kind.scoresOnTrend, "\(kind.rawValue) started smoothing unannounced")
        }
    }

    /// A real baseline has spread in it. A perfectly flat one has no dispersion, so
    /// every z is legitimately zero and there is nothing to test.
    private func baseline(count: Int = 60, mean: Double = 55, spread: Double = 5) -> [Double] {
        (0..<count).map { mean + spread * sin(Double($0) * 1.1) }
    }

    @Test("one bad HRV night moves the call far less than a bad week")
    func oneNightIsNotAWeek() {
        // Same person, same baseline. One rough night against seven of them.
        let steady = baseline()
        let oneBadNight = steady + [20.0]
        let aBadWeek = steady + Array(repeating: 20.0, count: 7)

        let single = BaselineEngine.evaluate(series: oneBadNight)!
        let sustained = BaselineEngine.evaluate(series: aBadWeek)!

        #expect(abs(single.trendZScore) < abs(sustained.trendZScore),
                "a week of bad nights has to read worse than one")
        #expect(abs(single.trendZScore) < abs(single.zScore),
                "smoothing is what stops one night dominating")
    }

    @Test("what is displayed is still today, never the smoothed figure")
    func displayStaysHonest() {
        let series = baseline() + [20.0]
        let reading = BaselineEngine.reading(kind: .hrv, series: series)!

        #expect(reading.value == 20.0, "the card must show the night that happened")
        #expect(reading.zScore == BaselineEngine.evaluate(series: series)!.zScore,
                "the displayed z is today's, so the words under it match the number")
        #expect(reading.scoringZ != reading.zScore, "but the engine scores the trend")
    }

    @Test("a metric that is not smoothed scores exactly what it displays")
    func unsmoothedMetricsAgree() {
        let series = baseline(mean: 52, spread: 3) + [70.0]
        let reading = BaselineEngine.reading(kind: .restingHeartRate, series: series)!
        #expect(reading.scoringZ == reading.zScore)
    }

    @Test("the engine uses the scoring z, so smoothing actually reaches the composite")
    func engineUsesScoringZ() {
        let spike = MetricReading(kind: .hrv, value: 20, baseline: 55,
                                  zScore: -3.0, scoringZ: -0.4, sampleCount: 60)
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: [spike], daysOfHistory: 60))

        // Scored on -0.4, not on -3.0. The composite is no longer -0.4 exactly, because
        // a single metric is damped rather than renormalised to the full weight — but it
        // is nowhere near what the raw z would have produced, which is what this asserts.
        let weight = try! #require(result.contributions.first).weight
        #expect(abs(result.composite - (-0.4 * weight)) < 0.0001,
                "composite was \(result.composite); the engine is still reading the raw z")
        #expect(result.composite > -0.5, "a smoothed metric produced a raw-z composite")
    }

    @Test("sleep and resting heart rate now outweigh HRV")
    func weightsFavourTheRobustInputs() {
        let weights = ReadinessEngine.weights
        let hrv = weights[.hrv] ?? 0
        #expect((weights[.sleepDebt] ?? 0) > hrv,
                "sleep is the most causally established and the most actionable")
        #expect((weights[.restingHeartRate] ?? 0) >= hrv,
                "resting heart rate is steadier and easier to trust")
    }

    @Test("no single metric can decide the day on its own")
    func noMetricDominates() {
        for (kind, weight) in ReadinessEngine.weights {
            #expect(weight < 0.5, "\(kind.rawValue) at \(weight) is the model by itself")
        }
    }

    @Test("changing how the score is produced changes the version stamped on it")
    func versionMovedWithTheMaths() {
        // Recommendations are persisted with this, so a score from the old weights and
        // one from the new must not claim to have come from the same model.
        #expect(ReadinessEngine.modelVersion != "v0.1.0")
    }
}
