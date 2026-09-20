import Foundation
import Testing
@testable import ReadinessCore

// Pins the recovery transfer and the shared score structure.
// See docs/superpowers/specs/2026-09-19-signal-scores-design.md.

private func reading(_ kind: MetricKind, z: Double) -> MetricReading {
    MetricReading(kind: kind, value: 0, baseline: 0, zScore: z, sampleCount: 30)
}

/// A morning uniformly `goodness` standard deviations better than baseline, so the
/// composite lands on `goodness` exactly and the transfer can be read straight off it.
private func morning(goodness: Double) -> [MetricReading] {
    ReadinessEngine.weights.keys.map { reading($0, z: goodness * $0.polarity) }
}

private func score(composite: Double) -> SignalScore {
    RecoveryScore.of(ReadinessEngine.evaluate(
        ReadinessInput(readings: morning(goodness: composite), daysOfHistory: 60)))
}

@Suite("Recovery transfer")
struct RecoveryTransferTests {

    /// The bug the whole spec exists for. The old ring ran the composite through a
    /// standard normal CDF as though it were a single z-score, but the composite is a
    /// weighted mean of five clamped z-scores and its own SD is about 0.5. The ring
    /// compressed into roughly 20...80 and never reached either end.
    @Test("a composite of zero is the middle of the scale")
    func neutralIsFifty() throws {
        #expect(try #require(score(composite: 0).value) == 50)
    }

    @Test("the band edges sit where the spec says", arguments: [
        (0.26, 67), (-0.26, 33), (1.20, 98), (-1.20, 2),
    ])
    func bandEdges(composite: Double, percent: Int) throws {
        let value = try #require(score(composite: composite).value)
        #expect(Int(value.rounded()) == percent)
    }

    /// Under the old transfer this day read as 17. The point of the change is that a
    /// genuinely bad morning produces a genuinely bad number.
    @Test("a bad morning reaches the bottom of the scale")
    func badMorningIsLow() throws {
        let value = try #require(score(composite: -1.0).value)
        #expect(value < 6, "a composite of -1.0 read as \(value)")
    }

    @Test("a good morning reaches the top of the scale")
    func goodMorningIsHigh() throws {
        let value = try #require(score(composite: 1.0).value)
        #expect(value > 94, "a composite of 1.0 read as \(value)")
    }

    @Test("the transfer never leaves 0...100")
    func bounded() throws {
        for composite in stride(from: -4.0, through: 4.0, by: 0.25) {
            let value = try #require(score(composite: composite).value)
            #expect((0...100).contains(value))
        }
    }

    @Test("the transfer rises with the composite everywhere")
    func monotone() throws {
        var previous = -1.0
        for composite in stride(from: -3.0, through: 3.0, by: 0.1) {
            let value = try #require(score(composite: composite).value)
            #expect(value >= previous)
            previous = value
        }
    }

    /// The scale is absolute: the same physiological deviation always produces the same
    /// number, for everyone. This is the property that rules out dividing by the user's
    /// own spread, which would make it a percentile wearing a percent sign.
    @Test("the transfer depends on nothing but the composite")
    func absoluteScale() throws {
        let short = RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0.5), daysOfHistory: 8)))
        let long = RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0.5), daysOfHistory: 400)))
        #expect(try #require(short.value) == #require(long.value))
    }
}

@Suite("Recovery bands")
struct RecoveryBandTests {

    @Test("bands follow the published thresholds", arguments: [
        (100.0, ScoreBand.green), (67.0, .green), (66.9, .yellow),
        (34.0, .yellow), (33.9, .red), (0.0, .red),
    ])
    func bands(percent: Double, expected: ScoreBand) {
        #expect(ScoreBand.recovery(percent: percent) == expected)
    }

    /// The regression this spec exists to prevent: the ring and the recommendation were
    /// two independent calibrations of the same quantity and could drift apart.
    @Test("the state never contradicts the score")
    func stateAgreesWithScore() throws {
        for composite in stride(from: -3.0, through: 3.0, by: 0.05) {
            let result = ReadinessEngine.evaluate(
                ReadinessInput(readings: morning(goodness: composite), daysOfHistory: 60))
            let percent = try #require(RecoveryScore.of(result).value)
            switch result.state {
            case .aboveBaseline: #expect(percent >= 67)
            case .atBaseline: #expect(percent >= 34 && percent < 67)
            case .belowBaseline: #expect(percent >= 15 && percent < 34)
            case .wellBelowBaseline: #expect(percent < 15)
            }
        }
    }

    /// Every state has to be reachable from physiology alone. The old thresholds put
    /// wellBelowBaseline at composite < -1.5 — roughly a 2.5-sigma day — so in practice
    /// it only ever arrived through the wrist-temperature gate.
    @Test("every state is reachable without a gate")
    func allStatesReachable() {
        let states = Set(stride(from: -3.0, through: 3.0, by: 0.05).map {
            ReadinessEngine.evaluate(
                ReadinessInput(readings: morning(goodness: $0), daysOfHistory: 60)).state
        })
        #expect(states == Set(ReadinessState.allCases))
    }

    /// Same argument one layer down: the session advice thresholded the composite on its
    /// own scale, so a red ring could sit above a "maintain".
    @Test("the training state never contradicts the score either")
    func trainingStateAgreesWithScore() {
        for composite in stride(from: -3.0, through: 3.0, by: 0.05) {
            let percent = RecoveryScore.percent(composite: composite)
            switch RecommendationEngine.trainingState(for: composite) {
            case .push: #expect(percent >= 67)
            case .maintain: #expect(percent >= 34 && percent < 67)
            case .reduce: #expect(percent >= 15 && percent < 34)
            case .recover: #expect(percent < 15)
            }
        }
    }
}

@Suite("Score contributions")
struct ScoreContributionTests {

    @Test("every input that voted is reported")
    func contributorsPresent() {
        let reported = Set(score(composite: 0.5).contributors.map(\.id))
        #expect(reported == Set(ReadinessEngine.weights.keys.map(\.rawValue)))
    }

    /// What makes the Insights screen honest: the rows have to add up to the number at
    /// the top, or they are decoration.
    @Test("contributor magnitudes sum to the distance from neutral")
    func magnitudesSumToScore() throws {
        for composite in [-1.5, -0.6, -0.1, 0.0, 0.4, 1.1] {
            let result = score(composite: composite)
            let value = try #require(result.value)
            let summed = result.contributors.reduce(0) { $0 + $1.magnitude }
            #expect(abs(summed - (value - 50)) < 0.01,
                    "composite \(composite): rows sum to \(summed), score sits \(value - 50) from neutral")
        }
    }

    /// Inputs that cancel still have to report the push they made. Attributing only the
    /// net movement would show every row at zero on a day when two strong signals
    /// disagreed, which is the day the breakdown matters most.
    @Test("opposing inputs report opposing magnitudes")
    func magnitudeSigns() throws {
        let readings = [reading(.hrv, z: 1.5), reading(.restingHeartRate, z: 1.5)]
        let result = RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: readings, daysOfHistory: 60)))
        let hrv = try #require(result.contributors.first { $0.id == MetricKind.hrv.rawValue })
        let rhr = try #require(result.contributors.first {
            $0.id == MetricKind.restingHeartRate.rawValue })
        // High HRV is good news. A resting heart rate 1.5 SD high is not.
        #expect(hrv.magnitude > 0)
        #expect(rhr.magnitude < 0)
    }

    @Test("contributor state reflects the direction of the reading")
    func contributorStates() {
        #expect(score(composite: 1.5).contributors.allSatisfy { $0.state == .optimal })
        #expect(score(composite: -1.5).contributors.allSatisfy { $0.state == .payAttention })
        #expect(score(composite: 0).contributors.allSatisfy { $0.state == .fine })
    }

    @Test("contributors carry the reading and the baseline they were judged against")
    func contributorsCarryValues() throws {
        let readings = [MetricReading(kind: .hrv, value: 48, baseline: 61,
                                      zScore: -1.2, sampleCount: 30)]
        let result = RecoveryScore.of(
            ReadinessEngine.evaluate(ReadinessInput(readings: readings, daysOfHistory: 60)),
            readings: readings)
        let hrv = try #require(result.contributors.first)
        #expect(hrv.value == 48)
        #expect(hrv.comparison == 61)
        #expect(hrv.unit == MetricKind.hrv.unit)
    }

    /// Sorted by what actually mattered today, not by a fixed order, so the screen leads
    /// with the reason rather than with whatever the enum happens to list first.
    @Test("contributors come back ranked by how much they moved the score")
    func contributorsRanked() {
        let readings = [reading(.hrv, z: -0.1), reading(.restingHeartRate, z: 2.0),
                        reading(.respiratoryRate, z: 0.2)]
        let result = RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: readings, daysOfHistory: 60)))
        #expect(result.contributors.first?.id == MetricKind.restingHeartRate.rawValue)
        let magnitudes = result.contributors.map { abs($0.magnitude) }
        #expect(magnitudes == magnitudes.sorted(by: >))
    }
}

@Suite("Score coverage")
struct ScoreCoverageTests {

    @Test("no readings means no score rather than a confident fifty")
    func noReadings() {
        let result = RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: [], daysOfHistory: 0)))
        #expect(result.value == nil)
        #expect(result.band == nil)
        #expect(result.coverage == .unavailable)
    }

    @Test("a short history is reported as building rather than hidden")
    func shortHistory() {
        let result = RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 0.2), daysOfHistory: 5)))
        #expect(result.coverage == .buildingBaseline)
        #expect(result.value != nil, "a building baseline still shows a number")
    }

    @Test("a missing stream is named rather than silently dropped")
    func missingNamed() {
        let partial = ReadinessEngine.weights.keys.filter { $0 != .bloodOxygen }
            .map { reading($0, z: 0) }
        let result = RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: partial, daysOfHistory: 60)))
        #expect(result.coverage == .partial)
        #expect(result.missing.contains { $0.contains(MetricKind.bloodOxygen.displayName) })
    }

    @Test("everything present reads as full coverage")
    func fullCoverage() {
        #expect(score(composite: 0.3).coverage == .full)
        #expect(score(composite: 0.3).missing.isEmpty)
    }

    /// A gate is the loudest thing the engine can say, so it cannot be left off the
    /// breakdown — the screen would show contributors that do not explain the number.
    @Test("a gate is reported alongside the contributors")
    func gateReported() throws {
        let result = RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 2.0),
                           wristTemperatureDeviationC: 0.8, daysOfHistory: 60)))
        #expect(result.gate == .elevatedWristTemperature)
        #expect(try #require(result.value) < 15,
                "a gated day cannot still show the ungated number")
    }
}
