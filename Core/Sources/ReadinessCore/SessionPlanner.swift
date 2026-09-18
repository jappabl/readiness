import Foundation

public struct PlannedExercise: Equatable, Sendable {
    public let name: String
    public let muscleGroup: MuscleGroup
    public let sets: Int
    public let reps: Int
    public let workingWeight: Double
    public let increment: Double
    public let rir: Int

    public init(name: String, muscleGroup: MuscleGroup, sets: Int, reps: Int,
                workingWeight: Double, increment: Double, rir: Int) {
        self.name = name
        self.muscleGroup = muscleGroup
        self.sets = sets
        self.reps = reps
        self.workingWeight = workingWeight
        self.increment = increment
        self.rir = rir
    }
}

public struct ProposedExercise: Equatable, Sendable {
    public let planned: PlannedExercise
    public let sets: Int
    public let load: Double
    public let rir: Int
    public let isDeferred: Bool

    public var changed: Bool {
        isDeferred || sets != planned.sets || load != planned.workingWeight || rir != planned.rir
    }
}

/// Turns the recommendation's adjustments into a concrete session, without ever
/// destroying the plan the user wrote. The original is always still there.
public enum SessionPlanner {

    public static func apply(_ adjustments: [SessionAdjustment],
                             to exercises: [PlannedExercise]) -> [ProposedExercise] {
        exercises.map { exercise in
            var sets = exercise.sets
            var load = exercise.workingWeight
            var rir = exercise.rir
            var deferred = false

            for adjustment in adjustments {
                switch adjustment {
                case .proceedAsPlanned:
                    break

                case .reduceWorkingSets(let percent):
                    // Never below a single working set: a session with no sets is a rest
                    // day, and that is a different recommendation.
                    let scaled = Double(sets) * (1 - Double(percent) / 100)
                    sets = max(1, Int(scaled.rounded()))

                case .capEffort(let cap):
                    // A cap only ever moves effort further from failure.
                    rir = max(rir, cap)

                case .reduceLoad(let percent):
                    let delta = load * Double(percent) / 100
                    let rounded = PlateMath.round(delta, toIncrement: exercise.increment)
                    load = max(exercise.increment, load - rounded)

                case .deferLowerBody:
                    if exercise.muscleGroup.isLowerBody { deferred = true }

                case .swapConditioningToZone2:
                    break   // Conditioning is not a lift, so it does not touch this list.
                }
            }

            return ProposedExercise(planned: exercise, sets: sets, load: load,
                                    rir: rir, isDeferred: deferred)
        }
    }
}
