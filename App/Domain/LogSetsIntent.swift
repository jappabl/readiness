import AppIntents
import SwiftData
import Foundation

/// Logging a set by saying it, between sets.
///
/// Rest is dead time and a phone is awkward with chalk on your hands, so the whole point
/// is that nothing needs tapping: you say one messy sentence and it becomes structured
/// sets. The hearing is `SpokenSetParser` and the deciding is `SpokenSetResolver`, both
/// pure and tested; this is the part that writes it down. The microphone inside the
/// logging screen goes through the same two, so the two routes cannot disagree.
struct LogSetsIntent: AppIntent {

    static var title: LocalizedStringResource = "Log sets"
    static var description = IntentDescription(
        "Say what you just lifted and Jett writes it down, including how it felt.")
    /// Stays in the background: the point is not to make somebody look at a screen.
    static var openAppWhenRun = false

    @Parameter(title: "What you did",
               requestValueDialog: "What did you just do?")
    var spoken: String

    // On the main actor because it writes to the app's own context, which lives there.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // The app's own container, so a set logged mid-rest is on screen by the time
        // the phone goes back in the bag.
        let context = Store.container.mainContext

        // Only the user's own lifts are candidates, so "felt heavy" can never be
        // mistaken for an exercise name.
        let templates = (try? context.fetch(FetchDescriptor<WorkoutTemplate>())) ?? []
        let programme = templates.flatMap { $0.orderedExercises }
        let metric = (try? context.fetch(FetchDescriptor<UserProfile>()))?
            .first?.unitsAreMetric ?? false

        // No screen is open, so there is no lift already in front of them to assume.
        let outcome = SpokenSetResolver.resolve(spoken,
                                                current: nil,
                                                programme: programme.map(\.plannedExercise),
                                                unitsAreMetric: metric)
        switch outcome {
        case .heardNothing:
            return .result(dialog: "I didn't catch any sets in that.")
        case .needsExercise:
            return .result(dialog: "Which lift was that?")
        case .needsReps:
            return .result(dialog: "How many reps?")
        case .ready(let resolution):
            let planned = programme.first {
                $0.name.caseInsensitiveCompare(resolution.exercise.name) == .orderedSame
            }
            let session = WorkoutSession.today(in: context, named: planned?.template?.name)
            SpokenSetWriter.write(resolution, muscleGroup: planned?.muscleGroup ?? .core,
                                  into: session, in: context)
            return .result(dialog: IntentDialog(
                stringLiteral: SpokenSetWriter.confirmation(resolution, metric: metric)))
        }
    }
}

/// Writing down what was heard, and reading it back.
///
/// Shared by Siri and the microphone in the logging screen: one place that turns a
/// resolution into rows, so the same sentence can never produce two different days.
enum SpokenSetWriter {

    @MainActor
    static func write(_ resolution: SpokenSetResolver.Resolution,
                      muscleGroup: MuscleGroup,
                      into session: WorkoutSession,
                      in context: ModelContext) {
        let startingOrder = session.sets.count
        for (offset, set) in resolution.sets.enumerated() {
            let logged = LoggedSet(
                exerciseName: resolution.exercise.name,
                muscleGroup: muscleGroup,
                load: set.load,
                reps: set.reps,
                rir: set.rir,
                order: startingOrder + offset,
                feel: resolution.feel)
            logged.session = session
            session.sets.append(logged)
            context.insert(logged)
        }
        try? context.save()
    }

    /// Spoken back by Siri, who has no screen to show it on.
    static func confirmation(_ resolution: SpokenSetResolver.Resolution,
                             metric: Bool) -> String {
        "Got it. " + understood(resolution, metric: metric) + "."
    }

    /// What was understood, not what was said. Hearing "three sets, felt heavy" is how
    /// somebody catches a misparse — read aloud by Siri, or read on the confirm card.
    static func understood(_ resolution: SpokenSetResolver.Resolution,
                           metric: Bool) -> String {
        // The reps are the thing worth reading back: "1 set of bench" tells somebody
        // nothing about whether it heard them right.
        let reps = resolution.sets.map(\.reps)
        let sets: String
        if let first = reps.first, reps.allSatisfy({ $0 == first }) {
            sets = "\(Copy.count(reps.count, "set")) of \(first)"
        } else {
            sets = reps.map(String.init).joined(separator: ", ")
        }
        var parts = ["\(sets) on \(resolution.exercise.name)"]
        if let load = resolution.sets.first?.load, load > 0 {
            let shown = metric ? load / SpokenSetResolver.poundsPerKilogram : load
            parts.append("at \(shown.formatted(.number.precision(.fractionLength(0)))) "
                         + (metric ? "kg" : "lb"))
        }
        if let rir = resolution.sets.first?.rir {
            parts.append(rir == 0 ? "to failure" : "\(rir) in reserve")
        }
        if let feel = resolution.feel { parts.append("felt \(feel.rawValue)") }
        return parts.joined(separator: ", ")
    }
}

/// The spoken phrases. `applicationName` is required in every one of them.
struct JettShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogSetsIntent(),
            phrases: [
                "Tell \(.applicationName) what I lifted",
                "Log a set with \(.applicationName)",
                "\(.applicationName) log this set",
            ],
            shortTitle: "Log sets",
            systemImageName: "waveform")
    }
}
