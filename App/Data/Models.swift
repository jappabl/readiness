import Foundation
import SwiftData

// MARK: - Program

/// A reusable session. The user's plan of record, which the agent may propose changes to
/// but never overwrites.
@Model
final class WorkoutTemplate {
    var name: String
    var order: Int
    @Relationship(deleteRule: .cascade, inverse: \TemplateExercise.template)
    var exercises: [TemplateExercise] = []

    init(name: String, order: Int = 0) {
        self.name = name
        self.order = order
    }

    var orderedExercises: [TemplateExercise] { exercises.sorted { $0.order < $1.order } }
}

@Model
final class TemplateExercise {
    var name: String
    var muscleGroupRaw: String
    var targetSets: Int
    var targetReps: Int
    var workingWeight: Double
    var increment: Double
    var targetRIR: Int
    var restSeconds: Int
    var order: Int
    var template: WorkoutTemplate?

    init(name: String, muscleGroup: MuscleGroup, targetSets: Int = 3, targetReps: Int = 5,
         workingWeight: Double, increment: Double = 5, targetRIR: Int = 2,
         restSeconds: Int = 180, order: Int = 0) {
        self.name = name
        self.muscleGroupRaw = muscleGroup.rawValue
        self.targetSets = targetSets
        self.targetReps = targetReps
        self.workingWeight = workingWeight
        self.increment = increment
        self.targetRIR = targetRIR
        self.restSeconds = restSeconds
        self.order = order
    }

    var muscleGroup: MuscleGroup { MuscleGroup(rawValue: muscleGroupRaw) ?? .core }

    var plannedExercise: PlannedExercise {
        PlannedExercise(name: name, muscleGroup: muscleGroup, sets: targetSets,
                        reps: targetReps, workingWeight: workingWeight,
                        increment: increment, rir: targetRIR)
    }
}

// MARK: - What actually happened

@Model
final class WorkoutSession {
    var date: Date
    var templateName: String
    var isComplete: Bool
    var sessionRPE: Double
    var startedAt: Date
    var finishedAt: Date?
    @Relationship(deleteRule: .cascade, inverse: \LoggedSet.session)
    var sets: [LoggedSet] = []

    init(date: Date, templateName: String) {
        self.date = date
        self.templateName = templateName
        self.isComplete = false
        self.sessionRPE = 0
        self.startedAt = Date()
    }

    var orderedSets: [LoggedSet] { sets.sorted { $0.order < $1.order } }

    var liftSets: [LiftSet] {
        sets.map { LiftSet(load: $0.load, reps: $0.reps, rir: $0.rir,
                           muscleGroup: $0.muscleGroup, isWarmup: $0.isWarmup) }
    }

    var load: SessionLoad {
        StrainEngine.sessionLoad(sets: liftSets, sessionRPE: sessionRPE)
    }
}

@Model
final class LoggedSet {
    var exerciseName: String
    var muscleGroupRaw: String
    var load: Double
    var reps: Int
    var rir: Int
    var isWarmup: Bool
    var order: Int
    var timestamp: Date
    var session: WorkoutSession?

    init(exerciseName: String, muscleGroup: MuscleGroup, load: Double, reps: Int,
         rir: Int, isWarmup: Bool = false, order: Int) {
        self.exerciseName = exerciseName
        self.muscleGroupRaw = muscleGroup.rawValue
        self.load = load
        self.reps = reps
        self.rir = rir
        self.isWarmup = isWarmup
        self.order = order
        self.timestamp = Date()
    }

    var muscleGroup: MuscleGroup { MuscleGroup(rawValue: muscleGroupRaw) ?? .core }
    /// Epley, which is the usual convention and good enough in the 1-10 rep range.
    var estimatedOneRepMax: Double { load * (1 + Double(reps) / 30.0) }
}

// MARK: - Daily record

@Model
final class CheckInRow {
    @Attribute(.unique) var date: Date
    var soreness: Int
    var energy: Int
    var stress: Int
    var mood: Int

    init(date: Date, checkIn: CheckIn) {
        self.date = date
        self.soreness = checkIn.soreness
        self.energy = checkIn.energy
        self.stress = checkIn.stress
        self.mood = checkIn.mood
    }

    var checkIn: CheckIn {
        CheckIn(soreness: soreness, energy: energy, stress: stress, mood: mood)
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

/// How the user answered the agent. This is the feedback loop: without it the app can
/// never find out whether its calls were worth making.
enum RecommendationResponse: String, Codable, CaseIterable {
    case accepted, modified, rejected
}

@Model
final class RecommendationRow {
    @Attribute(.unique) var date: Date
    var stateRaw: String
    var composite: Double
    var evidenceJSON: String
    var adjustmentsJSON: String
    var uncertaintyJSON: String
    var modelVersion: String
    var confidenceRaw: String
    var gateRaw: String?
    var responseRaw: String?

    init(date: Date, readiness: ReadinessResult, recommendation: Recommendation) {
        self.date = date
        self.stateRaw = recommendation.state.rawValue
        self.composite = readiness.composite
        self.modelVersion = recommendation.modelVersion
        self.confidenceRaw = recommendation.confidence.rawValue
        self.gateRaw = readiness.gateApplied?.rawValue
        self.evidenceJSON = Self.encode(recommendation.evidence)
        self.adjustmentsJSON = Self.encode(recommendation.adjustments)
        self.uncertaintyJSON = Self.encode(recommendation.uncertainty)
    }

    /// Refresh today's row in place. The row is kept rather than replaced so that a
    /// response already recorded against it survives.
    func update(readiness: ReadinessResult, recommendation: Recommendation) {
        stateRaw = recommendation.state.rawValue
        composite = readiness.composite
        modelVersion = recommendation.modelVersion
        confidenceRaw = recommendation.confidence.rawValue
        gateRaw = readiness.gateApplied?.rawValue
        evidenceJSON = Self.encode(recommendation.evidence)
        adjustmentsJSON = Self.encode(recommendation.adjustments)
        uncertaintyJSON = Self.encode(recommendation.uncertainty)
    }

    private static func encode<T: Encodable>(_ value: T) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    private func decode<T: Decodable>(_ json: String, as type: T.Type) -> T? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    var state: TrainingState { TrainingState(rawValue: stateRaw) ?? .maintain }
    var confidence: ReadinessConfidence { ReadinessConfidence(rawValue: confidenceRaw) ?? .low }
    var gate: ReadinessGate? { gateRaw.flatMap(ReadinessGate.init(rawValue:)) }
    var response: RecommendationResponse? { responseRaw.flatMap(RecommendationResponse.init(rawValue:)) }
    var evidence: [InputContribution] { decode(evidenceJSON, as: [InputContribution].self) ?? [] }
    var adjustments: [SessionAdjustment] { decode(adjustmentsJSON, as: [SessionAdjustment].self) ?? [] }
    var uncertainty: [String] { decode(uncertaintyJSON, as: [String].self) ?? [] }
}

/// User-stated context the agent is allowed to rely on.
@Model
final class UserProfile {
    var goal: String
    var limitations: String
    var unitsAreMetric: Bool

    init(goal: String = "", limitations: String = "", unitsAreMetric: Bool = false) {
        self.goal = goal
        self.limitations = limitations
        self.unitsAreMetric = unitsAreMetric
    }
}
