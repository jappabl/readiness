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
        /// The session's middle rep count, kept for anything that wants one number.
        public let reps: Int
        public let rir: Int
        public let progression: TrainingProgression
        /// Per exercise, in the same order. A heavy press and a lateral raise do not
        /// belong at the same rep count, and one number for a whole session is how the
        /// old presets ended up prescribing sets of five lateral raises.
        public let repsPerExercise: [Int]

        public init(name: String, exercises: [Exercise], sets: Int, reps: Int, rir: Int,
                    progression: TrainingProgression, repsPerExercise: [Int] = []) {
            self.name = name
            self.exercises = exercises
            self.sets = sets
            self.reps = reps
            self.rir = rir
            self.progression = progression
            self.repsPerExercise = repsPerExercise.isEmpty
                ? Array(repeating: reps, count: exercises.count) : repsPerExercise
        }
    }

    public struct Split: Sendable {
        public let name: String
        public let sessions: [Plan]
    }

    /// Bridged from the catalog, so there is one list of exercises rather than two.
    private static func exercise(_ entry: CatalogExercise) -> Exercise {
        Exercise(name: entry.name, muscle: entry.muscle,
                 requiredEquipment: {
                     switch entry.equipment {
                     case .barbell: return .barbell
                     case .machine: return .machine
                     case .dumbbells: return .dumbbells
                     case .bodyweight: return .bodyweight
                     }
                 }(),
                 increment: entry.increment,
                 // Carried through, not dropped. Emptying this makes every test that
                 // asks "does this plan respect an injury" pass by asking nothing.
                 loadedAreas: entry.loads)
    }

    public static func allowedExerciseNames(equipment: EquipmentAccess,
                                            limitations: Set<PhysicalLimitation>?) -> [String] {
        // The coach's substitution list. Experience is not a filter here: this answers
        // "what could this person do", and somebody who has been lifting for a decade
        // asking Jett for a swap should not be offered a beginner's shortlist.
        ExerciseCatalog.available(equipment: equipment, limitations: limitations,
                                  experience: .experienced).map(\.name)
    }

    /// Fill a session's slots with the best exercise available for each.
    ///
    /// A slot names the versions it would like in order, then falls back to anything
    /// else in the same pattern. A slot with nothing left is dropped rather than
    /// substituted from another pattern: a push day with two rows in it would be worse
    /// than a push day with five movements.
    private static func fill(_ template: SplitCatalog.Template,
                             from allowed: [CatalogExercise],
                             experience: TrainingExperience) -> Plan? {
        var used: Set<String> = []
        var chosen: [Exercise] = []
        var reps: [Int] = []
        for slot in template.slots {
            let candidates = slot.prefer.compactMap { id in
                allowed.first { $0.id == id }
            } + allowed.filter { $0.pattern == slot.pattern }
            guard let pick = candidates.first(where: { !used.contains($0.id) }) else { continue }
            used.insert(pick.id)
            chosen.append(exercise(pick))
            reps.append(slot.reps)
        }
        guard chosen.count >= 3 else { return nil }
        // Sets scale with experience and the rep count does not. Six movements at three
        // sets is eighteen sets and an hour, which is right for somebody who has been
        // doing this and a lot for somebody in their first month.
        return Plan(name: template.name, exercises: chosen,
                    sets: experience == .new ? 2 : 3,
                    reps: Int(reps.reduce(0, +) / max(1, reps.count)),
                    rir: experience == .new ? 3 : 2,
                    progression: experience.progression,
                    repsPerExercise: reps)
    }

    public static func make(experience: TrainingExperience, equipment: EquipmentAccess,
                            limitations: Set<PhysicalLimitation>?) -> [Plan] {
        splits(experience: experience, equipment: equipment, limitations: limitations)
            .flatMap(\.sessions)
    }

    /// The split to start somebody on, from everything onboarding asked.
    ///
    /// Frequency decides the shape of the week, which is the thing that actually
    /// separates a programme from a list of exercises. Never nil for a real answer:
    /// landing on an empty Train tab after answering eight questions is the thing this
    /// exists to stop.
    public static func recommended(experience: TrainingExperience, equipment: EquipmentAccess,
                                   limitations: Set<PhysicalLimitation>?,
                                   frequency: TrainingFrequency) -> Split? {
        let allowed = ExerciseCatalog.available(equipment: equipment, limitations: limitations,
                                                experience: experience)
        guard !allowed.isEmpty else { return nil }
        let sessions = SplitCatalog.week(for: frequency)
            .compactMap { fill($0, from: allowed, experience: experience) }
        guard !sessions.isEmpty else { return nil }
        return Split(name: SplitCatalog.name(for: frequency), sessions: sessions)
    }

    /// Every split worth offering, with the one their week fits first.
    public static func splits(experience: TrainingExperience, equipment: EquipmentAccess,
                              limitations: Set<PhysicalLimitation>?) -> [Split] {
        let allowed = ExerciseCatalog.available(equipment: equipment, limitations: limitations,
                                                experience: experience)
        guard !allowed.isEmpty else { return [] }
        return TrainingFrequency.allCases.compactMap { frequency in
            let sessions = SplitCatalog.week(for: frequency)
                .compactMap { fill($0, from: allowed, experience: experience) }
            guard !sessions.isEmpty else { return nil }
            return Split(name: SplitCatalog.name(for: frequency), sessions: sessions)
        }
    }
}
