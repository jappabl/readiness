import Foundation
import Testing
@testable import ReadinessCore

/// Recovery for somebody who granted Health access to sleep and declined the heart
/// metrics — one tap apart in the permission sheet, and the whole population of
/// third-party sleep trackers.
///
/// Sleep debt is one-sided by construction: owing nothing is the best it gets, so its
/// aligned z is never positive. When it was the only input that could vote, the ring was
/// capped at 50 however well somebody slept — "Recovery 50, Middling" beside "Sleep 97"
/// off the same stream — and `StrainScore.target(recovery:)` read that ring, so the same
/// person was told to aim for 57 where a fully tracked one with identical sleep got 82.
@Suite("Recovery from sleep alone")
struct SleepOnlyRecoveryTests {

    private func debtOnly(hours: Double) -> ReadinessResult {
        ReadinessEngine.evaluate(ReadinessInput(readings: [
            MetricReading(kind: .sleepDebt, value: hours, baseline: 0,
                          zScore: hours / SleepDebt.hoursPerDeviation, sampleCount: 30)
        ], daysOfHistory: 60))
    }

    private func sleep(_ value: Double) -> SignalScore {
        SignalScore(kind: .sleep, value: value, band: .sleep(percent: value), contributors: [],
                    coverage: .full, missing: [], modelVersion: "test")
    }

    private func recovery(sleep score: Double, debt: Double) -> SignalScore {
        RecoveryScore.of(debtOnly(hours: debt), readings: [
            MetricReading(kind: .sleepDebt, value: debt, baseline: 0,
                          zScore: debt / SleepDebt.hoursPerDeviation, sampleCount: 30)
        ], sleep: sleep(score))
    }

    /// The headline: sleeping well now reads as recovered.
    @Test("a flawless sleeper is not stuck at the middle")
    func goodSleepReadsRecovered() throws {
        let value = try #require(recovery(sleep: 97, debt: 0).value)
        #expect(value > 67, "a 97 sleep score with no debt read \(value)")
    }

    /// And it still grades, in both directions, rather than swapping one ceiling for a
    /// flat number.
    @Test("it tracks the sleep it is derived from")
    func tracksSleep() throws {
        let values = try [97.0, 85, 70, 55, 40].map {
            try #require(recovery(sleep: $0, debt: 0).value)
        }
        #expect(zip(values, values.dropFirst()).allSatisfy { $1 < $0 },
                "not monotonic in sleep: \(values)")
        #expect(try #require(values.last) < 50, "a poor sleeper still reads middling")
    }

    /// Debt has not stopped mattering — it is the accumulated half of the same picture.
    @Test("a standing balance still pulls it down")
    func debtStillCounts() throws {
        let rested = try #require(recovery(sleep: 90, debt: 0).value)
        let owing = try #require(recovery(sleep: 90, debt: SleepDebt.maximumHours).value)
        #expect(owing < rested - 20, "\(SleepDebt.maximumHours) h of debt moved it from \(rested) to \(owing)")
    }

    /// The screen must not argue with itself: whatever it reads, it has to say what it
    /// could not see.
    @Test("it still says what is missing")
    func stillDiscloses() {
        let result = recovery(sleep: 97, debt: 0)
        #expect(result.coverage != .full)
        #expect(!result.missing.isEmpty)
    }

    /// The breakdown has to explain its own headline, which is the whole reason the night
    /// appears as a row rather than silently moving the number.
    @Test("the rows account for the number", arguments: [0.0, 2.0, 7.0])
    func rowsSum(debt: Double) throws {
        let result = recovery(sleep: 88, debt: debt)
        let value = try #require(result.value)
        let summed = result.contributors.reduce(0) { $0 + $1.magnitude }
        #expect(abs(summed - (value - RecoveryScore.neutral)) < 0.01,
                "rows \(summed) against \(value - RecoveryScore.neutral)")
        #expect(result.contributor("night") != nil, "no row for the night it came from")
    }

    /// And a full panel is untouched — this is a fallback, not a new input.
    @Test("a full panel does not use it")
    func fullPanelUnchanged() throws {
        let readings = ReadinessEngine.weights.keys.map {
            MetricReading(kind: $0, value: 40, baseline: 40, zScore: 0, sampleCount: 30)
        }
        let result = ReadinessEngine.evaluate(ReadinessInput(readings: readings,
                                                             daysOfHistory: 60))
        let withSleep = RecoveryScore.of(result, readings: readings, sleep: sleep(97))
        let without = RecoveryScore.of(result, readings: readings)
        #expect(withSleep.value == without.value)
    }
}
