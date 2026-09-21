import Testing
@testable import ReadinessCore

private func readiness(_ composite: Double,
                       gate: ReadinessGate? = nil,
                       confidence: ReadinessConfidence = .normal) -> ReadinessResult {
    let contributions = MetricKind.allCases.map {
        InputContribution(kind: $0, zScore: composite, weight: ReadinessEngine.weights[$0] ?? 0,
                          points: (ReadinessEngine.weights[$0] ?? 0) * composite)
    }
    return ReadinessResult(state: ReadinessEngine.state(for: composite), composite: composite,
                           contributions: contributions, confidence: confidence,
                           gateApplied: gate, modelVersion: ReadinessEngine.modelVersion)
}

@Suite("Check-in folds in, but never takes over")
struct CheckInTests {

    @Test("a neutral morning moves nothing")
    func neutralIsZero() {
        #expect(abs(RecommendationEngine.checkInShift(.neutral)) < 1e-9)
    }

    @Test("a great morning helps, a terrible one hurts")
    func directionIsRight() {
        let best = RecommendationEngine.checkInShift(CheckIn(soreness: 5, energy: 5, stress: 5, mood: 5))
        let worst = RecommendationEngine.checkInShift(CheckIn(soreness: 1, energy: 1, stress: 1, mood: 1))
        #expect(best > 0)
        #expect(worst < 0)
    }

    @Test("what someone reports is information, not an override")
    func shiftIsBounded() {
        for soreness in 1...5 {
            for energy in 1...5 {
                let shift = RecommendationEngine.checkInShift(
                    CheckIn(soreness: soreness, energy: energy, stress: energy, mood: soreness))
                #expect(abs(shift) <= 0.5)
            }
        }
    }

    @Test("a perfect check-in cannot rescue a genuinely bad morning")
    func checkInCannotOverridePhysiology() {
        let rec = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(-2.5),
                                checkIn: CheckIn(soreness: 5, energy: 5, stress: 5, mood: 5)))
        #expect(rec.state == .recover)
    }

    /// The borderline moved when the states stopped being thresholds on the composite
    /// and started being read off the recovery scale. A composite of -0.4 is now a
    /// reduce day on its own; an ordinary morning is the one a bad check-in can move.
    @Test("a poor check-in can pull a borderline day down a state")
    func checkInMovesBorderlineDays() {
        // Borderline means near the line, and the line moved. A composite of 0 is now
        // the middle of maintain rather than its edge, and no check-in shift is meant
        // to carry a morning from the middle of a band to the one below it.
        let borderline = -0.4
        let without = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(borderline)))
        let with = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(borderline),
                                checkIn: CheckIn(soreness: 1, energy: 1, stress: 1, mood: 1)))
        #expect(without.state == .maintain)
        #expect(with.state == .reduce)
    }
}

@Suite("Training state")
struct TrainingStateTests {

    @Test("a strong morning says push")
    func strongDayPushes() {
        #expect(RecommendationEngine.recommend(RecommendationInput(readiness: readiness(1.0))).state == .push)
    }

    @Test("an ordinary morning says maintain")
    func ordinaryDayMaintains() {
        #expect(RecommendationEngine.recommend(RecommendationInput(readiness: readiness(0.0))).state == .maintain)
    }

    /// -0.4 used to say reduce and now says maintain, which is the recalibration
    /// working rather than a test drifting: two thirds of a standard deviation off
    /// somebody's own average is an ordinary Tuesday, and telling them to cut sets for
    /// it is why the score read as strict. -0.9 is a genuinely down morning.
    @Test("a down morning says reduce")
    func downDayReduces() {
        #expect(RecommendationEngine.recommend(RecommendationInput(readiness: readiness(-0.9))).state == .reduce)
    }

    /// And the other side of the same line, so the boundary is pinned from both sides
    /// rather than only from below.
    @Test("a slightly down morning is left alone")
    func slightlyDownDayMaintains() {
        #expect(RecommendationEngine.recommend(RecommendationInput(readiness: readiness(-0.4))).state == .maintain)
    }

    @Test("a badly down morning says recover")
    func badDayRecovers() {
        #expect(RecommendationEngine.recommend(RecommendationInput(readiness: readiness(-2.0))).state == .recover)
    }

    @Test("an illness flag overrides even a strong morning")
    func illnessForcesRecover() {
        let rec = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(2.0, gate: .elevatedWristTemperature)))
        #expect(rec.state == .recover)
    }

    @Test("a load spike cancels a push without inventing a bad day")
    func loadSpikeCapsPush() {
        let rec = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(1.5), acwr: 1.8))
        #expect(rec.state == .maintain)
    }

    @Test("a load spike never upgrades a poor morning")
    func loadSpikeDoesNotRescue() {
        let rec = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(-2.0), acwr: 1.8))
        #expect(rec.state == .recover)
    }
}

@Suite("Adjustments are concrete: 'take it easy' is not an answer")
struct AdjustmentTests {

    @Test("every state proposes at least one concrete action")
    func neverEmpty() {
        for composite in [1.5, 0.0, -1.0, -2.0] {
            let rec = RecommendationEngine.recommend(RecommendationInput(readiness: readiness(composite)))
            #expect(!rec.adjustments.isEmpty, "no action proposed at composite \(composite)")
        }
    }

    @Test("a good day proceeds as planned, and says only that")
    func goodDayProceeds() {
        let rec = RecommendationEngine.recommend(RecommendationInput(readiness: readiness(1.0)))
        #expect(rec.adjustments == [.proceedAsPlanned])
    }

    @Test("a reduce day trims sets and caps effort rather than cutting load")
    func reduceTrimsVolume() {
        let rec = RecommendationEngine.recommend(RecommendationInput(readiness: readiness(-0.9)))
        #expect(rec.adjustments.contains { if case .reduceWorkingSets = $0 { return true }; return false })
        #expect(rec.adjustments.contains { if case .capEffort = $0 { return true }; return false })
        #expect(!rec.adjustments.contains(.proceedAsPlanned))
    }

    @Test("a recover day with lower body planned moves the lower body work")
    func recoverDefersLowerBody() {
        let rec = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(-2.0), hasPlannedLowerBody: true))
        #expect(rec.adjustments.contains(.deferLowerBody))
    }

    @Test("nothing is deferred that was not planned in the first place")
    func doesNotDeferWhatWasNotPlanned() {
        let rec = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(-2.0), hasPlannedLowerBody: false))
        #expect(!rec.adjustments.contains(.deferLowerBody))
    }

    @Test("a recover day swaps planned intervals for easy aerobic work")
    func recoverSwapsConditioning() {
        let rec = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(-2.0), hasPlannedConditioning: true))
        #expect(rec.adjustments.contains(.swapConditioningToZone2))
    }
}

@Suite("Evidence and uncertainty")
struct EvidenceTests {

    @Test("evidence leads with the strongest drag, and stays short")
    func evidenceIsRankedAndShort() {
        let rec = RecommendationEngine.recommend(RecommendationInput(readiness: readiness(-1.0)))
        #expect(rec.evidence.count <= 3)
        // Derived from the weights rather than named, so rebalancing the model does not
        // silently turn this into a test of nothing.
        let heaviest = ReadinessEngine.weights.max { $0.value < $1.value }?.key
        #expect(rec.evidence.first?.kind == heaviest,
                "with equal z across metrics, the heaviest weight drags most")
    }

    @Test("a thin baseline is admitted, not hidden")
    func lowConfidenceIsStated() {
        let rec = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(0, confidence: .low)))
        #expect(rec.confidence == .low)
        #expect(!rec.uncertainty.isEmpty)
    }

    @Test("a missing check-in is named as a gap")
    func missingCheckInIsNamed() {
        let rec = RecommendationEngine.recommend(RecommendationInput(readiness: readiness(0)))
        #expect(rec.uncertainty.contains { $0.lowercased().contains("check-in") })
    }

    @Test("a complete picture claims no false gaps")
    func completeDataHasNoCheckInCaveat() {
        let rec = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(0), checkIn: .neutral, acwr: 1.0))
        #expect(!rec.uncertainty.contains { $0.lowercased().contains("check-in") })
    }

    @Test("the recommendation records which model produced it")
    func versionTravels() {
        let rec = RecommendationEngine.recommend(RecommendationInput(readiness: readiness(0)))
        #expect(rec.modelVersion == ReadinessEngine.modelVersion)
    }
}
