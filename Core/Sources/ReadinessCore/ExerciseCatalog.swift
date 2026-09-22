import Foundation

/// What a movement is, rather than what it is called.
///
/// Every exercise belongs to one, and a pattern's entries are ordered from the most
/// forgiving version to the least. That one ordering does two jobs: it decides where a
/// beginner enters, and it decides what to offer when somebody swaps something out. Two
/// lists would have drifted, and the drift would have shown up as a beginner being
/// offered a barbell bench as a *substitute* for the machine press we gave them.
public enum MovementPattern: String, Sendable, Codable, CaseIterable {
    case horizontalPress, verticalPress, horizontalPull, verticalPull
    case squat, hinge, lunge
    case chestIsolation, shoulderIsolation, backIsolation
    case bicep, tricep, quadIsolation, hamstringIsolation, calf, core

    /// Whether this is the heavy part of a session or the part that finishes it off.
    public var isCompound: Bool {
        switch self {
        case .horizontalPress, .verticalPress, .horizontalPull, .verticalPull,
             .squat, .hinge, .lunge:
            return true
        default:
            return false
        }
    }
}

/// What you need to hand.
public enum ExerciseEquipment: String, Sendable, Codable {
    case barbell, machine, dumbbells, bodyweight

    /// Whether somebody with this much equipment can do it.
    func available(to access: EquipmentAccess) -> Bool {
        switch access {
        case .fullGym: return true
        case .dumbbells: return self == .dumbbells || self == .bodyweight
        case .bodyweight: return self == .bodyweight
        }
    }
}

public struct CatalogExercise: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let pattern: MovementPattern
    public let muscle: MuscleGroup
    public let equipment: ExerciseEquipment
    /// The smallest load step that makes sense, in pounds. Zero for bodyweight.
    public let increment: Double
    /// Joints and areas this puts under load, checked against what somebody has ruled out.
    let loads: Set<PhysicalLimitation>
    /// Whether somebody in their first year should be handed this.
    ///
    /// Not a difficulty rating. The line is what happens when a rep fails on your own
    /// with nobody watching: a barbell bench pins you, a back squat has to be dumped off
    /// your back, a loaded barbell hinge folds a spine that has not learned the pattern.
    /// A split squat is harder than a leg press and perfectly safe to fail, so it is not
    /// on this list.
    public let needsExperience: Bool

    init(_ id: String, _ name: String, _ pattern: MovementPattern, _ muscle: MuscleGroup,
         _ equipment: ExerciseEquipment, increment: Double,
         loads: Set<PhysicalLimitation>, needsExperience: Bool = false) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.muscle = muscle
        self.equipment = equipment
        self.increment = increment
        self.loads = loads
        self.needsExperience = needsExperience
    }
}

/// Everything the app knows how to prescribe.
///
/// Deliberately small. Eleven thousand exercises behind a paid API is a subscription, a
/// network round trip and a dependency on somebody else's uptime, in a basement gym with
/// no signal, for a list that never changes. Seventy covers every pattern at every
/// equipment level, fits in the binary and is always there.
public enum ExerciseCatalog {

    /// What each movement actually loads, which is not the same as what it trains.
    ///
    /// `loads` used to be generous: every upper-body movement claimed the shoulder,
    /// curls and triceps pushdowns included. The filter is a hard exclusion, so
    /// declaring a shoulder injury deleted the entire upper body. A tester coming back
    /// from one was handed a single session, Lower, for ever: no rows, no pulldowns, no
    /// arms. Somebody who cannot press can still row and curl, and answering an injury
    /// by deleting half of training is not caution, it is uselessness wearing caution's
    /// coat.
    ///
    /// The line drawn here: a movement claims a joint when that joint takes the load.
    /// For the shoulder that is pressing in any direction, anything overhead, hanging
    /// from a bar, a deep fly stretch, and bearing weight through the arm. A horizontal
    /// row, a curl, a pushdown and the rear-delt rehab work do not.
    ///
    /// The knee had the same fault in the other direction: a bad knee deleted the lower
    /// body, because a hip hinge and a calf raise both claimed it. A Romanian deadlift
    /// is a hinge with soft knees and a calf raise happens below them. Squatting,
    /// lunging, stepping, a leg extension and a deadlift do claim the knee.
    ///
    /// Not a clinical judgement and no substitute for one. It is the difference between
    /// a list somebody can train from and a list with nothing in it.
    public static let all: [CatalogExercise] = [
        // Horizontal press
        .init("bench", "Barbell bench press", .horizontalPress, .chest, .barbell,
              increment: 5, loads: [.shoulders], needsExperience: true),
        .init("machine-press", "Machine chest press", .horizontalPress, .chest, .machine,
              increment: 5, loads: [.shoulders]),
        .init("incline-machine", "Incline chest press machine", .horizontalPress, .chest, .machine,
              increment: 5, loads: [.shoulders]),
        .init("db-bench", "Dumbbell bench press", .horizontalPress, .chest, .dumbbells,
              increment: 5, loads: [.shoulders]),
        .init("db-incline", "Incline dumbbell press", .horizontalPress, .chest, .dumbbells,
              increment: 5, loads: [.shoulders]),
        .init("pushup", "Push-up", .horizontalPress, .chest, .bodyweight,
              increment: 0, loads: [.shoulders]),
        .init("decline-pushup", "Decline push-up", .horizontalPress, .chest, .bodyweight,
              increment: 0, loads: [.shoulders]),
        .init("knee-pushup", "Knee push-up", .horizontalPress, .chest, .bodyweight,
              increment: 0, loads: [.shoulders]),

        // Vertical press
        .init("ohp", "Overhead press", .verticalPress, .shoulders, .barbell,
              increment: 5, loads: [.shoulders, .lowerBack], needsExperience: true),
        .init("machine-shoulder", "Machine shoulder press", .verticalPress, .shoulders, .machine,
              increment: 5, loads: [.shoulders]),
        .init("db-shoulder", "Dumbbell shoulder press", .verticalPress, .shoulders, .dumbbells,
              increment: 5, loads: [.shoulders]),
        .init("pike-pushup", "Pike push-up", .verticalPress, .shoulders, .bodyweight,
              increment: 0, loads: [.shoulders]),

        // Horizontal pull
        .init("bb-row", "Barbell row", .horizontalPull, .back, .barbell,
              increment: 5, loads: [.lowerBack, .shoulders], needsExperience: true),
        .init("chest-row", "Chest-supported row", .horizontalPull, .back, .machine,
              increment: 5, loads: []),
        .init("cable-row", "Seated cable row", .horizontalPull, .back, .machine,
              increment: 5, loads: []),
        .init("db-row", "One-arm dumbbell row", .horizontalPull, .back, .dumbbells,
              increment: 5, loads: []),
        .init("db-chest-row", "Chest-supported dumbbell row", .horizontalPull, .back, .dumbbells,
              increment: 5, loads: []),
        .init("inverted-row", "Inverted row", .horizontalPull, .back, .bodyweight,
              increment: 0, loads: []),
        .init("towel-row", "Towel row", .horizontalPull, .back, .bodyweight,
              increment: 0, loads: []),

        // Vertical pull
        .init("pullup", "Pull-up", .verticalPull, .back, .bodyweight,
              increment: 0, loads: [.shoulders]),
        .init("pulldown", "Lat pulldown", .verticalPull, .back, .machine,
              increment: 5, loads: [.shoulders]),
        .init("db-pullover", "Dumbbell pullover", .verticalPull, .back, .dumbbells,
              increment: 5, loads: [.shoulders]),

        // Squat
        .init("back-squat", "Back squat", .squat, .quads, .barbell,
              increment: 5, loads: [.lowerBack, .knees, .shoulders], needsExperience: true),
        .init("leg-press", "Leg press", .squat, .quads, .machine,
              increment: 10, loads: [.knees, .lowerBack]),
        .init("hack-squat", "Hack squat", .squat, .quads, .machine,
              increment: 10, loads: [.knees, .lowerBack]),
        .init("goblet-squat", "Goblet squat", .squat, .quads, .dumbbells,
              increment: 5, loads: [.knees, .lowerBack]),
        .init("bw-squat", "Bodyweight squat", .squat, .quads, .bodyweight,
              increment: 0, loads: [.knees]),

        // Hinge
        .init("deadlift", "Deadlift", .hinge, .hamstrings, .barbell,
              increment: 10, loads: [.lowerBack, .knees], needsExperience: true),
        .init("bb-rdl", "Romanian deadlift", .hinge, .hamstrings, .barbell,
              increment: 5, loads: [.lowerBack], needsExperience: true),
        .init("db-rdl", "Dumbbell Romanian deadlift", .hinge, .hamstrings, .dumbbells,
              increment: 5, loads: [.lowerBack]),
        .init("back-ext", "Back extension", .hinge, .hamstrings, .machine,
              increment: 5, loads: [.lowerBack]),
        .init("sl-rdl", "Single-leg Romanian deadlift", .hinge, .hamstrings, .bodyweight,
              increment: 0, loads: [.lowerBack]),
        .init("glute-bridge", "Glute bridge", .hinge, .glutes, .bodyweight,
              increment: 0, loads: [.lowerBack]),

        // Lunge
        .init("bulgarian", "Bulgarian split squat", .lunge, .quads, .dumbbells,
              increment: 5, loads: [.knees]),
        .init("db-lunge", "Dumbbell reverse lunge", .lunge, .glutes, .dumbbells,
              increment: 5, loads: [.knees]),
        .init("step-up", "Dumbbell step-up", .lunge, .glutes, .dumbbells,
              increment: 5, loads: [.knees]),
        .init("bw-lunge", "Reverse lunge", .lunge, .quads, .bodyweight,
              increment: 0, loads: [.knees]),
        .init("bw-split-squat", "Split squat", .lunge, .quads, .bodyweight,
              increment: 0, loads: [.knees]),

        // Isolation, upper
        .init("cable-fly", "Cable fly", .chestIsolation, .chest, .machine,
              increment: 5, loads: [.shoulders]),
        .init("pec-deck", "Pec deck", .chestIsolation, .chest, .machine,
              increment: 5, loads: [.shoulders]),
        .init("db-fly", "Dumbbell fly", .chestIsolation, .chest, .dumbbells,
              increment: 5, loads: [.shoulders]),
        .init("lateral-raise", "Lateral raise", .shoulderIsolation, .shoulders, .dumbbells,
              increment: 2.5, loads: [.shoulders]),
        .init("cable-lateral", "Cable lateral raise", .shoulderIsolation, .shoulders, .machine,
              increment: 2.5, loads: [.shoulders]),
        .init("rear-delt-fly", "Rear delt fly", .shoulderIsolation, .shoulders, .dumbbells,
              increment: 2.5, loads: [.shoulders]),
        .init("face-pull", "Face pull", .backIsolation, .back, .machine,
              increment: 5, loads: []),
        .init("prone-ytw", "Prone Y-T-W raise", .backIsolation, .back, .bodyweight,
              increment: 0, loads: []),
        .init("snow-angel", "Prone reverse snow angel", .backIsolation, .back, .bodyweight,
              increment: 0, loads: []),

        // Arms
        .init("bb-curl", "Barbell curl", .bicep, .arms, .barbell,
              increment: 5, loads: []),
        .init("db-curl", "Dumbbell curl", .bicep, .arms, .dumbbells,
              increment: 2.5, loads: []),
        .init("incline-curl", "Incline dumbbell curl", .bicep, .arms, .dumbbells,
              increment: 2.5, loads: []),
        .init("hammer-curl", "Hammer curl", .bicep, .arms, .dumbbells,
              increment: 2.5, loads: []),
        .init("chin-up", "Chin-up", .bicep, .arms, .bodyweight,
              increment: 0, loads: [.shoulders]),
        .init("pushdown", "Triceps pushdown", .tricep, .arms, .machine,
              increment: 5, loads: []),
        .init("overhead-ext", "Overhead triceps extension", .tricep, .arms, .dumbbells,
              increment: 2.5, loads: [.shoulders]),
        .init("skullcrusher", "Skullcrusher", .tricep, .arms, .dumbbells,
              increment: 2.5, loads: []),
        .init("chair-dip", "Chair dip", .tricep, .arms, .bodyweight,
              increment: 0, loads: [.shoulders]),
        .init("diamond-pushup", "Diamond push-up", .tricep, .arms, .bodyweight,
              increment: 0, loads: [.shoulders]),

        // Isolation, lower
        .init("leg-ext", "Leg extension", .quadIsolation, .quads, .machine,
              increment: 5, loads: [.knees]),
        .init("leg-curl", "Seated leg curl", .hamstringIsolation, .hamstrings, .machine,
              increment: 5, loads: []),
        .init("nordic", "Nordic curl", .hamstringIsolation, .hamstrings, .bodyweight,
              increment: 0, loads: [.knees]),
        .init("calf-raise", "Standing calf raise", .calf, .quads, .machine,
              increment: 10, loads: []),
        .init("db-calf", "Dumbbell calf raise", .calf, .quads, .dumbbells,
              increment: 5, loads: []),
        .init("bw-calf", "Calf raise", .calf, .quads, .bodyweight,
              increment: 0, loads: []),

        // Core
        .init("dead-bug", "Dead bug", .core, .core, .bodyweight, increment: 0, loads: [.lowerBack]),
        .init("plank", "Plank", .core, .core, .bodyweight, increment: 0, loads: [.lowerBack, .shoulders]),
        .init("hanging-raise", "Hanging knee raise", .core, .core, .bodyweight,
              increment: 0, loads: [.shoulders, .lowerBack]),
    ]

    private static let byID: [String: CatalogExercise] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func exercise(_ id: String) -> CatalogExercise? { byID[id] }
    public static func named(_ name: String) -> CatalogExercise? {
        all.first { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    /// Everything somebody can actually do, given what they have and what hurts.
    ///
    /// Nil limitations means the injury question has not been answered, and prescribing
    /// a back squat before knowing about somebody's back is the one mistake here worth
    /// refusing to make.
    public static func available(equipment: EquipmentAccess,
                                 limitations: Set<PhysicalLimitation>?,
                                 experience: TrainingExperience) -> [CatalogExercise] {
        guard let limitations else { return [] }
        return all.filter { exercise in
            exercise.equipment.available(to: equipment)
                && exercise.loads.isDisjoint(with: limitations)
                && (!exercise.needsExperience || experience != .new)
        }
    }

    /// What to offer instead of this one.
    ///
    /// The same movement, on whatever they have, minus what hurts and minus the lifts a
    /// first-year lifter should not be handed alone. Empty when nothing fits, which is
    /// the honest answer: the app offers a swap or it offers a delete, never a guess.
    public static func alternatives(to exercise: CatalogExercise,
                                    equipment: EquipmentAccess,
                                    limitations: Set<PhysicalLimitation>?,
                                    experience: TrainingExperience) -> [CatalogExercise] {
        available(equipment: equipment, limitations: limitations, experience: experience)
            .filter { $0.pattern == exercise.pattern && $0.id != exercise.id }
    }
}
