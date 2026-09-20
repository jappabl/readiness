import Foundation
import Testing
@testable import ReadinessCore

// Pins the recovery transfer and the shared score structure.
// See docs/superpowers/specs/2026-09-19-signal-scores-design.md.

private func reading(_ kind: MetricKind, z: Double, samples: Int = 30) -> MetricReading {
    MetricReading(kind: kind, value: 0, baseline: 0, zScore: z, sampleCount: samples)
}

/// Confidence comes from how many samples each baseline rests on, not from how long the
/// series is — a night of phone sleep is enough to lengthen the series while every heart
/// metric is still judged against two readings.
private func thinMorning(goodness: Double, samples: Int) -> [MetricReading] {
    ReadinessEngine.weights.keys.map {
        reading($0, z: goodness * $0.polarity, samples: samples)
    }
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

    /// Re-pointed when compositeScale moved from 0.6 to 0.75. At 0.6 the score was
    /// over-spread — at a realistic correlation between the inputs it ordered a healthy
    /// person to recover one day in five.
    /// The transfer itself, not a morning run through the engine: past about a standard
    /// deviation the per-contribution clamp starts holding individual inputs back, so a
    /// uniform morning no longer lands on its own number. That clamp is deliberate and
    /// has its own tests; this is the curve underneath it.
    @Test("the band edges sit where the spec says", arguments: [
        (0.3299, 67), (-0.3299, 33), (1.5403, 98), (-1.5403, 2), (0.0, 50),
    ])
    func bandEdges(composite: Double, percent: Int) {
        #expect(Int(RecoveryScore.percent(composite: composite).rounded()) == percent)
    }

    /// Under the old transfer this day read as 17. The point of the change is that a
    /// genuinely bad morning produces a genuinely bad number.
    @Test("a bad morning reaches the bottom of the scale")
    func badMorningIsLow() throws {
        let value = try #require(score(composite: -1.0).value)
        #expect(value < 10, "a composite of -1.0 read as \(value)")
    }

    @Test("a good morning reaches the top of the scale")
    func goodMorningIsHigh() throws {
        let value = try #require(score(composite: 1.0).value)
        #expect(value > 90, "a composite of 1.0 read as \(value)")
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
            case .belowBaseline: #expect(percent >= 10 && percent < 34)
            case .wellBelowBaseline: #expect(percent < 10)
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
            case .reduce: #expect(percent >= 10 && percent < 34)
            case .recover: #expect(percent < 10)
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
            ReadinessInput(readings: thinMorning(goodness: 0.2, samples: 5),
                           daysOfHistory: 5)))
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

@Suite("No single input runs the ring")
struct SingleInputTests {

    /// One metric could red-line the whole score. A resting heart rate two beats above
    /// normal, with every other reading exactly average, produced a 34 and a "reduce".
    @Test("one metric alone cannot leave the middle band")
    func oneMetricCannotRedLine() throws {
        for kind in ReadinessEngine.weights.keys {
            for z in [2.0, 3.0, 5.0] {
                let readings = ReadinessEngine.weights.keys.map {
                    reading($0, z: $0 == kind ? z * -$0.polarity : 0)
                }
                let value = try #require(RecoveryScore.of(ReadinessEngine.evaluate(
                    ReadinessInput(readings: readings, daysOfHistory: 60))).value)
                #expect(value >= 25,
                        "\(kind) alone at \(z) SD dragged the whole score to \(value)")
            }
        }
    }

    /// Renormalising over whatever survived handed the absent streams' votes to whoever
    /// showed up: a lone blood-oxygen reading — weight 0.07 — scored the same as a full
    /// panel saying the same thing.
    @Test("a lone light-weight metric does not score like a full panel")
    func loneMetricIsDamped() throws {
        let alone = try #require(RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: [reading(.bloodOxygen, z: -1.0)],
                           daysOfHistory: 60))).value)
        #expect(alone > 35, "one blood oxygen reading scored the day at \(alone)")
    }

    /// But a thin panel still has to be able to say something.
    @Test("a partial panel still moves")
    func partialPanelStillWorks() throws {
        let readings = [reading(.hrv, z: -2.0), reading(.restingHeartRate, z: 2.0),
                        reading(.sleepDebt, z: 2.0)]
        let value = try #require(RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: readings, daysOfHistory: 60))).value)
        #expect(value < 25, "three streams all badly down only reached \(value)")
    }
}

@Suite("Gates say what they mean")
struct GateContractTests {

    /// The load-spike gate's own explanation says it "cannot make a good morning bad".
    /// It took seventy-six points off one, producing a red ring above an at-baseline
    /// state and a "maintain" — the exact disagreement the score mapping exists to stop.
    @Test("a load spike cancels a green light without making the day red")
    func loadSpikeCapsRatherThanCrushes() throws {
        let result = RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 1.0), acwr: 1.8, daysOfHistory: 60)))
        let value = try #require(result.value)
        #expect(value < 67, "the spike did not cancel the green light")
        #expect(value >= 34, "the spike crushed the day to \(value)")
        #expect(result.band == .yellow)
    }

    @Test("illness still takes the day to the bottom")
    func illnessCrushes() throws {
        let result = RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: 2.0),
                           wristTemperatureDeviationC: 0.8, daysOfHistory: 60)))
        #expect(try #require(result.value) < 10)
    }

    /// On a morning already below the ceiling the gate changes nothing, and a
    /// zero-magnitude row at the top of the list made the summary announce "Nothing
    /// stood out today" under the worst score the model can produce.
    @Test("a gate that moved nothing is not listed, and the summary still says something")
    func gateThatChangedNothing() {
        let result = RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: morning(goodness: -2.5),
                           wristTemperatureDeviationC: 0.8, daysOfHistory: 60)))
        #expect(!result.contributors.contains { $0.id == ReadinessGate.elevatedWristTemperature.rawValue })
        #expect(!result.summary.contains("Nothing stood out"))
    }
}

@Suite("A thin baseline says so")
struct ThinBaselineTests {

    /// `.buildingBaseline` used to be unreachable whenever any stream was absent, so a
    /// day-8 score was presented with exactly the confidence of a day-60 one.
    @Test("a thin baseline outranks a missing stream in the coverage note")
    func thinBaselineWins() {
        let partial = ReadinessEngine.weights.keys.filter { $0 != .bloodOxygen }
            .map { reading($0, z: 0, samples: 5) }
        let result = RecoveryScore.of(ReadinessEngine.evaluate(
            ReadinessInput(readings: partial, daysOfHistory: 5)))
        #expect(result.coverage == .buildingBaseline)
    }
}

@Suite("Confidence follows the baselines, not the calendar")
struct ConfidenceSourceTests {

    /// The commonest first-run profile there is: months of iPhone sleep, a watch bought
    /// this week. The series is long, every heart baseline rests on two readings, and the
    /// app used to present that morning with exactly the confidence of a sixtieth one.
    @Test("a long series with thin baselines is still low confidence")
    func longSeriesThinBaselines() {
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: thinMorning(goodness: 0.3, samples: 2),
                           daysOfHistory: 180))
        #expect(result.confidence == .low)
        #expect(RecoveryScore.of(result).coverage == .buildingBaseline)
    }

    /// One thin stream is enough to soften the whole call, because it votes like the rest.
    @Test("the thinnest baseline decides")
    func thinnestDecides() {
        var readings = thinMorning(goodness: 0.3, samples: 60)
        readings[0] = reading(readings[0].kind, z: 0.3 * readings[0].kind.polarity, samples: 3)
        #expect(ReadinessEngine.evaluate(
            ReadinessInput(readings: readings, daysOfHistory: 180)).confidence == .low)
    }

    @Test("well-established baselines read as normal confidence")
    func establishedBaselines() {
        #expect(ReadinessEngine.evaluate(
            ReadinessInput(readings: thinMorning(goodness: 0.3, samples: 60),
                           daysOfHistory: 60)).confidence == .normal)
    }
}
