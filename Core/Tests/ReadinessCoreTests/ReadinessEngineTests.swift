import Testing
@testable import ReadinessCore

private func reading(_ kind: MetricKind, z: Double) -> MetricReading {
    MetricReading(kind: kind, value: 0, baseline: 0, zScore: z, sampleCount: 30)
}

/// A morning that is uniformly `goodness` standard deviations *better* than baseline.
/// Raw z is flipped per metric, because a high resting heart rate and a high HRV
/// mean opposite things.
private func morning(goodness: Double) -> [MetricReading] {
    MetricKind.allCases.map { reading($0, z: goodness * $0.polarity) }
}

private func morning(goodness: Double, overriding kind: MetricKind, rawZ: Double) -> [MetricReading] {
    morning(goodness: goodness).map { $0.kind == kind ? reading(kind, z: rawZ) : $0 }
}

@Suite("Readiness weights")
struct ReadinessWeightTests {

    @Test("every weighted input has a weight")
    func everyInputWeighted() {
        for kind in MetricKind.allCases {
            #expect(ReadinessEngine.weights[kind] != nil, "\(kind) has no weight")
        }
    }

    @Test("weights sum to exactly 1.0 so composite is a weighted mean of z-scores")
    func weightsSumToOne() {
        let total = ReadinessEngine.weights.values.reduce(0, +)
        #expect(abs(total - 1.0) < 1e-9)
    }

    /// Replaces an earlier test that asserted HRV carried the heaviest weight. That was
    /// the original spec's decision and it has been reversed deliberately: HRV is the
    /// noisiest input the app reads, and it held the largest share of the call only
    /// because convention says it should. The durable rule is the one below.
    @Test("the noisiest input never carries the most weight")
    func smoothedInputsDoNotLead() {
        let smoothed = ReadinessEngine.weights.filter { $0.key.scoresOnTrend }
        let heaviest = ReadinessEngine.weights.values.max() ?? 0
        for (kind, weight) in smoothed {
            #expect(weight < heaviest,
                    "\(kind.rawValue) needs smoothing to be trusted, so it cannot lead")
        }
    }
}

@Suite("Readiness state mapping")
struct ReadinessStateTests {

    @Test("a day exactly on baseline reads as at-baseline with zero composite")
    func flatDayIsAtBaseline() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0), daysOfHistory: 60))
        #expect(result.state == .atBaseline)
        #expect(abs(result.composite) < 1e-9)
    }

    @Test("a uniformly strong morning reads as above baseline")
    func strongDayIsAboveBaseline() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 1.0), daysOfHistory: 60))
        #expect(result.state == .aboveBaseline)
        #expect(abs(result.composite - 1.0) < 1e-9)
    }

    @Test("a uniformly poor morning reads as well below baseline")
    func poorDayIsWellBelowBaseline() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: -2.0), daysOfHistory: 60))
        #expect(result.state == .wellBelowBaseline)
    }

    /// Was written at goodness -1.0, which the old thresholds called mild. It is not:
    /// every metric a full standard deviation the wrong way at once is past the 1st
    /// percentile of the composite's own distribution. Calling that "mildly poor" was
    /// the miscalibration, so the test now asks the question at a composite that really
    /// is a middling-bad morning.
    @Test("a mildly poor morning is below baseline, not well below")
    func mildlyPoorDayIsBelowBaseline() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: -0.4), daysOfHistory: 60))
        #expect(result.state == .belowBaseline)
    }

    @Test("inverted metrics push the right way: a high resting heart rate hurts readiness")
    func highRestingHeartRateLowersReadiness() {
        let flat = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0), daysOfHistory: 60))
        let elevated = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0, overriding: .restingHeartRate, rawZ: 2.0),
                           daysOfHistory: 60))
        #expect(elevated.composite < flat.composite)
    }

    @Test("a high HRV helps readiness — the mirror of the resting heart rate case")
    func highHRVRaisesReadiness() {
        let flat = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0), daysOfHistory: 60))
        let strong = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0, overriding: .hrv, rawZ: 2.0),
                           daysOfHistory: 60))
        #expect(strong.composite > flat.composite)
    }
}

@Suite("Readiness decomposition — spec AC3")
struct ReadinessDecompositionTests {

    @Test("per-input contributions sum to the composite, verifiable by hand")
    func contributionsSumToComposite() {
        let readings: [MetricReading] = [
            reading(.hrv, z: -1.4),
            reading(.restingHeartRate, z: 0.8),
            reading(.sleepDebt, z: 1.2),
            reading(.respiratoryRate, z: -0.3),
            reading(.bloodOxygen, z: 0.1),
        ]
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: readings, daysOfHistory: 60))
        let summed = result.contributions.reduce(0) { $0 + $1.points }
        #expect(abs(summed - result.composite) < 1e-9)
    }

    @Test("with every input present a contribution is exactly weight times polarity-adjusted z")
    func contributionIsWeightTimesZ() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0, overriding: .hrv, rawZ: -1.0),
                           daysOfHistory: 60))
        let hrv = result.contributions.first { $0.kind == .hrv }
        #expect(hrv != nil)
        let expected = (ReadinessEngine.weights[.hrv] ?? 0) * -1.0
        #expect(abs((hrv?.points ?? 0) - expected) < 1e-9)
    }

    @Test("every supplied reading produces a contribution")
    func allReadingsContribute() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0.5), daysOfHistory: 60))
        #expect(result.contributions.count == MetricKind.allCases.count)
    }

    @Test("the result records which model version produced it")
    func resultCarriesModelVersion() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0), daysOfHistory: 60))
        #expect(result.modelVersion == ReadinessEngine.modelVersion)
    }

    @Test("the largest negative contributor is identifiable for the Explain screen")
    func largestNegativeContributorIsFindable() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0, overriding: .sleepDebt, rawZ: 2.0),
                           daysOfHistory: 60))
        let worst = result.contributions.min { $0.points < $1.points }
        #expect(worst?.kind == .sleepDebt)
    }
}

@Suite("Readiness gates and guards")
struct ReadinessGateTests {

    @Test("elevated wrist temperature clamps the day regardless of a strong HRV")
    func wristTemperatureGateOverrides() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 2.0),
                           wristTemperatureDeviationC: 0.8,
                           daysOfHistory: 60))
        #expect(result.state == .wellBelowBaseline)
        #expect(result.gateApplied == .elevatedWristTemperature)
    }

    @Test("a wrist temperature below the gate does not clamp anything")
    func normalWristTemperatureDoesNotGate() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 2.0),
                           wristTemperatureDeviationC: 0.1,
                           daysOfHistory: 60))
        #expect(result.state == .aboveBaseline)
        #expect(result.gateApplied == nil)
    }

    @Test("an acute load spike caps an otherwise strong day at baseline")
    func acwrSpikeCapsUpgrade() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 2.0), acwr: 1.8, daysOfHistory: 60))
        #expect(result.state == .atBaseline)
        #expect(result.gateApplied == .acuteLoadSpike)
    }

    @Test("an acute load spike never upgrades a bad day")
    func acwrSpikeDoesNotRescueBadDay() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: -2.0), acwr: 1.8, daysOfHistory: 60))
        #expect(result.state == .wellBelowBaseline)
    }

    @Test("an ACWR inside the safe band changes nothing")
    func normalAcwrDoesNotGate() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 2.0), acwr: 1.1, daysOfHistory: 60))
        #expect(result.state == .aboveBaseline)
        #expect(result.gateApplied == nil)
    }

    @Test("one wild reading cannot dominate: z-scores are clamped")
    func singleDayIsNeverDecisive() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0, overriding: .hrv, rawZ: -50),
                           daysOfHistory: 60))
        let hrvPoints = result.contributions.first { $0.kind == .hrv }?.points ?? 0
        #expect(hrvPoints > -2.0, "a single absurd reading swung the composite to \(hrvPoints)")
    }
}

@Suite("Readiness confidence")
struct ReadinessConfidenceTests {

    @Test("fewer than 14 days of history reports low confidence")
    func shortHistoryIsLowConfidence() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0), daysOfHistory: 9))
        #expect(result.confidence == .low)
    }

    @Test("a full baseline window reports normal confidence")
    func longHistoryIsNormalConfidence() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0), daysOfHistory: 60))
        #expect(result.confidence == .normal)
    }

    @Test("exactly 14 days is confident — the threshold is inclusive")
    func thresholdIsInclusive() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0), daysOfHistory: 14))
        #expect(result.confidence == .normal)
    }

    @Test("a missing input is renormalised away, not counted as a zero")
    func missingInputsAreSkipped() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: [reading(.hrv, z: -2.0)], daysOfHistory: 60))
        #expect(result.contributions.count == 1)
        // Was wellBelowBaseline. One metric alone is now damped and clamped, on purpose:
        // renormalising to full weight handed the four absent streams' votes to whoever
        // showed up, and a lone reading could order a rest day by itself. It still has to
        // read the day rather than dilute toward zero, which is what this now asserts.
        #expect(result.state == .belowBaseline,
                "with only HRV present it should still read the day, not dilute toward zero")
        #expect(result.composite < -0.2)
    }

    @Test("no readings at all is low confidence and at baseline rather than a crash")
    func noReadingsIsSafe() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: [], daysOfHistory: 0))
        #expect(result.state == .atBaseline)
        #expect(result.confidence == .low)
    }
}
