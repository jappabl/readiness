import Foundation

/// These are starter defaults, not inferred working weights or automatic load raises.
public enum TrainingProgression: String, Sendable, Codable {
    case linear, repsThenLoad, plannedBlocks
    public var guidance: String {
        switch self {
        case .linear: return "Repeat the lifts. Add the smallest available load only after all reps are comfortable at target effort."
        case .repsThenLoad: return "Build reps at the same load before increasing weight; avoid raising load every session."
        case .plannedBlocks: return "Use planned training blocks and logged performance; do not assume session-to-session linear gains."
        }
    }
}

public enum StarterPrograms {
    public enum Equipment: Sendable { case barbell, machine, dumbbells, bodyweight }
    public struct Exercise: Sendable {
        public let name: String
        public let muscle: MuscleGroup
        public let requiredEquipment: Equipment
        public let increment: Double
        let loadedAreas: Set<PhysicalLimitation>
    }
    public struct Plan: Sendable {
        public let name: String
        public let exercises: [Exercise]
        public let sets: Int
        public let reps: Int
        public let rir: Int
        public let progression: TrainingProgression
    }

    public struct Split: Sendable {
        public let name: String
        public let sessions: [Plan]
    }

    private static let catalog: [Exercise] = [
        .init(name: "Back squat", muscle: .quads, requiredEquipment: .barbell, increment: 5, loadedAreas: [.lowerBack, .knees, .shoulders]),
        .init(name: "Romanian deadlift", muscle: .hamstrings, requiredEquipment: .barbell, increment: 5, loadedAreas: [.lowerBack, .knees]),
        .init(name: "Leg press", muscle: .quads, requiredEquipment: .machine, increment: 10, loadedAreas: [.lowerBack, .knees]),
        .init(name: "Bench press", muscle: .chest, requiredEquipment: .barbell, increment: 5, loadedAreas: [.shoulders]),
        .init(name: "Barbell row", muscle: .back, requiredEquipment: .barbell, increment: 5, loadedAreas: [.lowerBack, .shoulders]),
        .init(name: "Overhead press", muscle: .shoulders, requiredEquipment: .barbell, increment: 5, loadedAreas: [.lowerBack, .shoulders]),
        .init(name: "Goblet squat", muscle: .quads, requiredEquipment: .dumbbells, increment: 5, loadedAreas: [.knees, .lowerBack, .shoulders]),
        .init(name: "Dumbbell Romanian deadlift", muscle: .hamstrings, requiredEquipment: .dumbbells, increment: 5, loadedAreas: [.lowerBack, .knees]),
        .init(name: "Dumbbell reverse lunge", muscle: .glutes, requiredEquipment: .dumbbells, increment: 5, loadedAreas: [.knees, .lowerBack]),
        .init(name: "Dumbbell floor press", muscle: .chest, requiredEquipment: .dumbbells, increment: 5, loadedAreas: [.shoulders]),
        .init(name: "Dumbbell row", muscle: .back, requiredEquipment: .dumbbells, increment: 5, loadedAreas: [.lowerBack, .shoulders]),
        .init(name: "Standing dumbbell press", muscle: .shoulders, requiredEquipment: .dumbbells, increment: 5, loadedAreas: [.lowerBack, .shoulders]),
        .init(name: "Lat pulldown", muscle: .back, requiredEquipment: .machine, increment: 5, loadedAreas: [.shoulders]),
        .init(name: "Seated leg curl", muscle: .hamstrings, requiredEquipment: .machine, increment: 5, loadedAreas: [.knees]),
        .init(name: "Dumbbell curl", muscle: .arms, requiredEquipment: .dumbbells, increment: 2.5, loadedAreas: [.shoulders]),
        .init(name: "Dumbbell lateral raise", muscle: .shoulders, requiredEquipment: .dumbbells, increment: 2.5, loadedAreas: [.shoulders]),
        .init(name: "Single-leg bodyweight deadlift", muscle: .hamstrings, requiredEquipment: .bodyweight, increment: 0, loadedAreas: [.lowerBack, .knees]),
        .init(name: "Pike push-up", muscle: .shoulders, requiredEquipment: .bodyweight, increment: 0, loadedAreas: [.shoulders, .lowerBack]),
        .init(name: "Prone W raise", muscle: .back, requiredEquipment: .bodyweight, increment: 0, loadedAreas: [.shoulders, .lowerBack]),
        .init(name: "Prone reverse snow angel", muscle: .back, requiredEquipment: .bodyweight, increment: 0, loadedAreas: [.shoulders, .lowerBack]),
        .init(name: "Dead bug", muscle: .core, requiredEquipment: .bodyweight, increment: 0, loadedAreas: [.lowerBack, .shoulders]),
        .init(name: "Bodyweight squat", muscle: .quads, requiredEquipment: .bodyweight, increment: 0, loadedAreas: [.knees, .lowerBack]),
        .init(name: "Glute bridge", muscle: .glutes, requiredEquipment: .bodyweight, increment: 0, loadedAreas: [.lowerBack, .knees]),
        .init(name: "Reverse lunge", muscle: .quads, requiredEquipment: .bodyweight, increment: 0, loadedAreas: [.knees, .lowerBack]),
        .init(name: "Push-up", muscle: .chest, requiredEquipment: .bodyweight, increment: 0, loadedAreas: [.shoulders, .lowerBack]),
        .init(name: "Knee push-up", muscle: .chest, requiredEquipment: .bodyweight, increment: 0, loadedAreas: [.shoulders, .knees]),
    ]

    private static func available(equipment: EquipmentAccess, limitations: Set<PhysicalLimitation>?) -> [Exercise] {
        guard let limitations else { return [] }
        return catalog.filter { exercise in
            let supported: Bool
            switch equipment {
            case .fullGym: supported = true
            case .dumbbells: supported = exercise.requiredEquipment == .dumbbells || exercise.requiredEquipment == .bodyweight
            case .bodyweight: supported = exercise.requiredEquipment == .bodyweight
            }
            return supported && exercise.loadedAreas.isDisjoint(with: limitations)
        }
    }

    public static func allowedExerciseNames(equipment: EquipmentAccess, limitations: Set<PhysicalLimitation>?) -> [String] {
        available(equipment: equipment, limitations: limitations).map(\.name)
    }

    public static func make(experience: TrainingExperience, equipment: EquipmentAccess,
                            limitations: Set<PhysicalLimitation>?) -> [Plan] {
        // Prefer a useful mix of movements over the first few catalog entries.
        // Filtering happens before selection so a restricted exercise cannot be used
        // merely to reach the intended session length.
        let allowed = available(equipment: equipment, limitations: limitations)
        let preferred: [String]
        switch equipment {
        case .fullGym:
            preferred = ["Back squat", "Romanian deadlift", "Leg press", "Seated leg curl", "Glute bridge",
                         "Bench press", "Barbell row", "Overhead press", "Lat pulldown", "Dumbbell curl", "Dead bug"]
        case .dumbbells:
            preferred = ["Goblet squat", "Dumbbell Romanian deadlift", "Dumbbell reverse lunge", "Glute bridge",
                         "Dumbbell floor press", "Dumbbell row", "Standing dumbbell press", "Dumbbell curl",
                         "Dumbbell lateral raise", "Dead bug"]
        case .bodyweight:
            preferred = ["Bodyweight squat", "Single-leg bodyweight deadlift", "Reverse lunge", "Glute bridge",
                         "Push-up", "Prone W raise", "Pike push-up", "Prone reverse snow angel", "Dead bug"]
        }
        let exercises = preferred.compactMap { name in allowed.first { $0.name == name } }
        let lower = Array(exercises.filter { $0.muscle.isLowerBody }.prefix(5))
        let upper = Array(exercises.filter { !$0.muscle.isLowerBody && $0.muscle != .core }.prefix(5))
        let core = Array(exercises.filter { $0.muscle == .core }.prefix(1))
        let full = Array(lower.prefix(2)) + Array(upper.prefix(2)) + core
        return [("Lower body", lower), ("Upper body", upper), ("Full body", full)].compactMap { name, lifts in
            guard !lifts.isEmpty else { return nil }
            return Plan(name: name, exercises: lifts, sets: experience == .new ? 2 : 3,
                        reps: experience == .experienced ? 5 : 8, rir: experience == .new ? 3 : 2,
                        progression: experience.progression)
        }
    }

    public static func splits(experience: TrainingExperience, equipment: EquipmentAccess,
                              limitations: Set<PhysicalLimitation>?) -> [Split] {
        let sessions = make(experience: experience, equipment: equipment, limitations: limitations)
        var result: [Split] = []
        if let full = sessions.first(where: { $0.name == "Full body" }) {
            result.append(Split(name: "Full body", sessions: [full]))
        }
        if let upper = sessions.first(where: { $0.name == "Upper body" }),
           let lower = sessions.first(where: { $0.name == "Lower body" }) {
            result.append(Split(name: "Upper / lower", sessions: [upper, lower]))
        }
        return result
    }
}
