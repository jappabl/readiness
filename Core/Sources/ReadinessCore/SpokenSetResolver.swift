import Foundation

/// From words to sets that can be written down.
///
/// `SpokenSetParser` reports what the sentence said. This decides what actually gets
/// logged: which lift when none was named, what weight when none was said, whose unit a
/// bare number is in, and what effort to record when the sentence only mentioned reps.
/// Both the Siri intent and the microphone inside the logging screen come through here,
/// so the two can never disagree about the same sentence.
public enum SpokenSetResolver {

    public static let poundsPerKilogram = 2.2046226218

    /// One set, in the units everything downstream stores: pounds.
    public struct Set: Equatable, Sendable {
        public let load: Double
        public let reps: Int
        public let rir: Int

        public init(load: Double, reps: Int, rir: Int) {
            self.load = load
            self.reps = reps
            self.rir = rir
        }
    }

    public struct Resolution: Equatable, Sendable {
        public let exercise: PlannedExercise
        public let sets: [Set]
        public let feel: SetFeel?
        /// What was said, kept so the user can always check what was heard.
        public let transcript: String
    }

    public enum Outcome: Equatable, Sendable {
        case ready(Resolution)
        /// Nothing loggable was said. Better than inventing a set out of noise.
        case heardNothing
        /// A lift was named or is on screen, but no rep count was said.
        case needsReps
        /// Reps were said, but there is no lift to attach them to.
        case needsExercise

        public var ready: Resolution? {
            if case let .ready(resolution) = self { return resolution }
            return nil
        }
    }

    /// - Parameters:
    ///   - current: the lift the user is looking at, used when they did not name one.
    ///   - programme: every lift they train, the only names that can be matched.
    ///   - unitsAreMetric: how they think about weight, used only for a bare number.
    public static func resolve(_ spoken: String,
                               current: PlannedExercise?,
                               programme: [PlannedExercise],
                               unitsAreMetric: Bool) -> Outcome {
        let known = programme.map(\.name)
        guard let log = SpokenSetParser.parse(spoken, knownExercises: known) else {
            return .heardNothing
        }

        let named = log.exercise.flatMap { name in
            programme.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }
        guard let exercise = named ?? current else {
            return log.reps.isEmpty ? .heardNothing : .needsExercise
        }
        guard !log.reps.isEmpty else { return .needsReps }

        let load = pounds(log.load, unit: log.loadUnit, metric: unitsAreMetric)
            ?? exercise.workingWeight
        let rir = log.rir ?? exercise.rir

        return .ready(Resolution(
            exercise: exercise,
            sets: log.reps.map { Set(load: load, reps: $0, rir: rir) },
            feel: log.feel,
            transcript: log.transcript))
    }

    /// A spoken unit always wins. Without one, the number is in whatever unit the user
    /// reads the rest of the app in, which is the only unit they could have meant.
    static func pounds(_ value: Double?, unit: SpokenLoadUnit?, metric: Bool) -> Double? {
        guard let value else { return nil }
        let isKilograms = unit.map { $0 == .kilograms } ?? metric
        return isKilograms ? value * poundsPerKilogram : value
    }
}
