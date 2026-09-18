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

    @Test("a poor check-in can pull a borderline day down a state")
    func checkInMovesBorderlineDays() {
        let without = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(-0.4)))
        let with = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness(-0.4),
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

    @Test("a down morning says reduce")
    func downDayReduces() {
        #expect(RecommendationEngine.recommend(RecommendationInput(readiness: readiness(-1.0))).state == .reduce)
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

@Suite("Adjustments are concrete — 'take it easy' is not an answer")
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
        let rec = RecommendationEngine.recommend(RecommendationInput(readiness: readiness(-1.0)))
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
        #expect(rec.evidence.first?.kind == .hrv, "HRV carries the most weight, so it should lead")
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
