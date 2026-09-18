import Foundation
import SwiftData

/// The lifts the user actually trains, and the weights they are currently working with.
/// This plus HealthKit is the entire input surface of the app (principle P1).
@Model
final class LiftConfig {
    var name: String
    var workingWeight: Double
    var increment: Double
    var repTarget: Int
    var rirTarget: Int
    var order: Int

    init(name: String, workingWeight: Double, increment: Double,
         repTarget: Int = 5, rirTarget: Int = 2, order: Int = 0) {
        self.name = name
        self.workingWeight = workingWeight
        self.increment = increment
        self.repTarget = repTarget
        self.rirTarget = rirTarget
        self.order = order
    }

    var lift: Lift {
        Lift(name: name, workingWeight: workingWeight, increment: increment,
             repTarget: repTarget, rirTarget: rirTarget)
    }
}

/// One row per day per metric: what it read, the rolling baseline, and the distance between.
@Model
final class DailyMetricRow {
    var date: Date
    var kindRaw: String
    var value: Double
    var baseline: Double
    var zScore: Double
    var sampleCount: Int
    var lowConfidence: Bool

    init(date: Date, kind: MetricKind, value: Double, baseline: Double,
         zScore: Double, sampleCount: Int, lowConfidence: Bool) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.value = value
        self.baseline = baseline
        self.zScore = zScore
        self.sampleCount = sampleCount
        self.lowConfidence = lowConfidence
    }

    var kind: MetricKind? { MetricKind(rawValue: kindRaw) }
}

/// One row per day. `modelVersion` is recorded from row one so a later change to the
/// weight vector can be evaluated retrospectively against the same outcomes (spec 4.2).
@Model
final class ReadinessRow {
    @Attribute(.unique) var date: Date
    var stateRaw: String
    var composite: Double
    var contributionsJSON: String
    var modelVersion: String
    var confidenceRaw: String
    var gateRaw: String?

    init(date: Date, result: ReadinessResult) {
        self.date = date
        self.stateRaw = result.state.rawValue
        self.composite = result.composite
        self.modelVersion = result.modelVersion
        self.confidenceRaw = result.confidence.rawValue
        self.gateRaw = result.gateApplied?.rawValue
        self.contributionsJSON =
            (try? JSONEncoder().encode(result.contributions))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    var state: ReadinessState { ReadinessState(rawValue: stateRaw) ?? .atBaseline }
    var confidence: ReadinessConfidence { ReadinessConfidence(rawValue: confidenceRaw) ?? .low }
    var gate: ReadinessGate? { gateRaw.flatMap(ReadinessGate.init(rawValue:)) }
    var contributions: [InputContribution] {
        guard let data = contributionsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([InputContribution].self, from: data)) ?? []
    }
}

@Model
final class PrescriptionRow {
    var id: UUID
    var date: Date
    var liftName: String
    var predictedLoad: Double
    var predictedReps: Int
    var targetRIR: Int
    var stateRaw: String
    var workingWeight: Double
    var increment: Double
    var appliedPercent: Double

    init(date: Date, prescription: Prescription, state: ReadinessState) {
        self.id = UUID()
        self.date = date
        self.liftName = prescription.lift.name
        self.predictedLoad = prescription.prescribedLoad
        self.predictedReps = prescription.repTarget
        self.targetRIR = prescription.rirTarget
        self.stateRaw = state.rawValue
        self.workingWeight = prescription.lift.workingWeight
        self.increment = prescription.lift.increment
        self.appliedPercent = prescription.appliedPercent
    }

    var state: ReadinessState { ReadinessState(rawValue: stateRaw) ?? .atBaseline }
}

/// The grading record. This table is the only asset that compounds, so it is designed
/// properly on day one (spec 3.4).
@Model
final class OutcomeRow {
    var prescriptionID: UUID
    var date: Date
    var liftName: String
    var achievedLoad: Double
    var achievedReps: Int
    var achievedRIR: Int
    var completedAsPrescribed: Bool
    var timestamp: Date

    init(prescriptionID: UUID, date: Date, liftName: String, achievedLoad: Double,
         achievedReps: Int, achievedRIR: Int, completedAsPrescribed: Bool) {
        self.prescriptionID = prescriptionID
        self.date = date
        self.liftName = liftName
        self.achievedLoad = achievedLoad
        self.achievedReps = achievedReps
        self.achievedRIR = achievedRIR
        self.completedAsPrescribed = completedAsPrescribed
        self.timestamp = Date()
    }
}
