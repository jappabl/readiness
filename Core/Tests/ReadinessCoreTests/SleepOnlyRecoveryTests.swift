import Foundation
import Testing
@testable import ReadinessCore

/// Recovery for somebody who granted Health access to sleep and declined the heart
/// metrics, one tap apart in the permission sheet, and the whole population of
/// third-party sleep trackers.
///
/// Sleep debt is one-sided by construction: owing nothing is the best it gets, so its
/// aligned z is never positive. When it was the only input that could vote, the ring was
/// capped at 50 however well somebody slept. "Recovery 50, Middling" beside "Sleep 97"
/// off the same stream, and `StrainScore.target(recovery:)` read that ring, so the same
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
        let readings = [MetricReading(kind: .sleepDebt, value: debt, baseline: 0,
                                      zScore: debt / SleepDebt.hoursPerDeviation,
                                      sampleCount: 30)]
        // The night goes in at the engine, so the state, the gates and the advice all see
        // the same number the ring does.
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: readings, daysOfHistory: 60, nightScore: score))
        return RecoveryScore.of(result, readings: readings)
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

    /// Debt has not stopped mattering: it is the accumulated half of the same picture.
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

    /// And a full panel is untouched: this is a fallback, not a new input.
    @Test("a full panel does not use it")
    func fullPanelUnchanged() throws {
        let readings = ReadinessEngine.weights.keys.map {
            MetricReading(kind: $0, value: 40, baseline: 40, zScore: 0, sampleCount: 30)
        }
        let withSleep = RecoveryScore.of(
            ReadinessEngine.evaluate(ReadinessInput(readings: readings, daysOfHistory: 60,
                                                    nightScore: 97)),
            readings: readings)
        let without = RecoveryScore.of(
            ReadinessEngine.evaluate(ReadinessInput(readings: readings, daysOfHistory: 60)),
            readings: readings)
        #expect(withSleep.value == without.value)
    }

    private func withHRV(samples: Int, sleepScore: Double = 97) -> SignalScore {
        // The morning after a watch arrives: HRV is present and utterly ordinary, and its
        // baseline holds `samples` readings.
        let inputs = [
            MetricReading(kind: .sleepDebt, value: 0, baseline: 0, zScore: 0, sampleCount: 30),
            MetricReading(kind: .hrv, value: 60, baseline: 60, zScore: 0, sampleCount: samples),
        ]
        return RecoveryScore.of(
            ReadinessEngine.evaluate(ReadinessInput(readings: inputs, daysOfHistory: 60,
                                                    nightScore: sleepScore)),
            readings: inputs)
    }

    /// Buying a watch must not be a cliff. On the second morning of HRV its baseline holds
    /// one sample, so it has no spread and its z is forced to zero, and that empty vote
    /// used to be enough to switch the fallback off, taking a settled sleeper from 97 to
    /// 50 overnight on sleep that had not changed.
    @Test("acquiring a sensor does not move the ring on its own")
    func noCliffOnNewSensor() throws {
        let before = try #require(recovery(sleep: 97, debt: 0).value)
        let firstMorning = try #require(withHRV(samples: 1).value)
        #expect(abs(firstMorning - before) < 5,
                "one empty HRV reading moved the ring from \(before) to \(firstMorning)")
    }

    /// And the handover is gradual, not a step somewhere else along the way.
    @Test("the night hands over as evidence accrues")
    func handoverIsGradual() throws {
        let values = try (0...20).map { try #require(withHRV(samples: $0).value) }
        let steps = zip(values, values.dropFirst()).map { abs($1 - $0) }
        #expect(steps.max()! < 5, "a \(steps.max()!)-point step: \(values)")
        #expect(values.last! < values.first!, "the night never let go: \(values)")
    }

    /// The breakdown has to explain the headline at the bottom of the scale too, which is
    /// the one morning it matters most. Three hours asleep, seven in the hole.
    @Test("the rows still account for a floored number")
    func rowsSumAtTheFloor() throws {
        for sleepScore in [33.0, 25, 10] {
            let result = recovery(sleep: sleepScore, debt: SleepDebt.maximumHours)
            let value = try #require(result.value)
            let summed = result.contributors.reduce(0) { $0 + $1.magnitude }
            #expect(abs(summed - (value - RecoveryScore.neutral)) < 0.01,
                    "sleep \(sleepScore): rows \(summed) against \(value - RecoveryScore.neutral)")
        }
    }

    private func spiking(sleep score: Double, acwr: Double) -> ReadinessResult {
        ReadinessEngine.evaluate(ReadinessInput(
            readings: [MetricReading(kind: .sleepDebt, value: 0, baseline: 0, zScore: 0,
                                     sampleCount: 30)],
            acwr: acwr, daysOfHistory: 60, nightScore: score))
    }

    /// The load-spike gate exists to stop the app waving somebody into a hard session on
    /// top of a spike. It keys off the readiness state, the state came off the composite,
    /// and a one-sided composite can never reach the threshold that arms it, so the one
    /// ring that could now show green was the one the gate could not reach.
    @Test("a training spike still caps a night-derived ring")
    func spikeGateReachesSleepOnly() throws {
        let spiked = spiking(sleep: 97, acwr: 2.0)
        #expect(spiked.gateApplied == .acuteLoadSpike, "the gate never armed")
        let value = try #require(RecoveryScore.of(spiked, readings: []).value)
        #expect(value <= RecoveryScore.ceiling(for: .acuteLoadSpike) + 0.01,
                "a 2.0 spike left the ring at \(value)")
    }

    @Test("and an ordinary load does not")
    func noSpikeNoGate() throws {
        let calm = spiking(sleep: 97, acwr: 1.0)
        #expect(calm.gateApplied == nil)
        #expect(try #require(RecoveryScore.of(calm, readings: []).value) > 67)
    }

    /// The ring and the words under it are read off the same number, which is the property
    /// `AppModel.recoveryScore`'s own comment claims and this path had quietly broken.
    @Test("the advice agrees with the ring", arguments: [97.0, 80, 65, 45, 20])
    func stateMatchesTheRing(sleepScore: Double) throws {
        let result = spiking(sleep: sleepScore, acwr: 1.0)
        let value = try #require(RecoveryScore.of(result, readings: []).value)
        #expect(result.state == ReadinessEngine.state(forPercent: value),
                "ring \(value) beside \(result.state)")
    }
}
