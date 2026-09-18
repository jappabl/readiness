import Foundation

public enum MuscleGroup: String, CaseIterable, Sendable, Codable {
    case quads, hamstrings, glutes, back, chest, shoulders, arms, core

    public var isLowerBody: Bool {
        switch self {
        case .quads, .hamstrings, .glutes: return true
        default: return false
        }
    }

    public var displayName: String {
        switch self {
        case .quads: return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes: return "Glutes"
        case .back: return "Back"
        case .chest: return "Chest"
        case .shoulders: return "Shoulders"
        case .arms: return "Arms"
        case .core: return "Core"
        }
    }
}

/// One working set, as actually performed.
public struct LiftSet: Equatable, Sendable, Codable {
    public let load: Double
    public let reps: Int
    /// Reps in reserve. Lower means closer to failure.
    public let rir: Int
    public let muscleGroup: MuscleGroup
    public let isWarmup: Bool

    public init(load: Double, reps: Int, rir: Int, muscleGroup: MuscleGroup, isWarmup: Bool = false) {
        self.load = load
        self.reps = reps
        self.rir = rir
        self.muscleGroup = muscleGroup
        self.isWarmup = isWarmup
    }
}

/// How the app thinks the user should train today. Four states, produced by a
/// deterministic layer — never by the language model.
public enum TrainingState: String, CaseIterable, Sendable, Codable {
    case push, maintain, reduce, recover
}

/// The morning subjective inputs. 1 is worst, 5 is best, for every field — so a higher
/// number always means a better morning and the arithmetic needs no special cases.
public struct CheckIn: Equatable, Sendable, Codable {
    public let soreness: Int
    public let energy: Int
    public let stress: Int
    public let mood: Int

    public init(soreness: Int, energy: Int, stress: Int, mood: Int) {
        self.soreness = soreness
        self.energy = energy
        self.stress = stress
        self.mood = mood
    }

    public static let neutral = CheckIn(soreness: 3, energy: 3, stress: 3, mood: 3)
}

/// The smallest concrete change that fits the evidence. Never "take it easy".
public enum SessionAdjustment: Equatable, Hashable, Sendable, Codable {
    case proceedAsPlanned
    case reduceWorkingSets(percent: Int)
    case capEffort(rir: Int)
    case reduceLoad(percent: Int)
    case deferLowerBody
    case swapConditioningToZone2
}

public struct Recommendation: Equatable, Sendable {
    public let state: TrainingState
    public let adjustments: [SessionAdjustment]
    public let evidence: [InputContribution]
    public let uncertainty: [String]
    public let confidence: ReadinessConfidence
    public let modelVersion: String
}
