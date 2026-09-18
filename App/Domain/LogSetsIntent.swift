import AppIntents
import SwiftData
import Foundation

/// Logging a set by saying it, between sets.
///
/// Rest is dead time and a phone is awkward with chalk on your hands, so the whole point
/// is that nothing needs tapping: you say one messy sentence and it becomes structured
/// sets. The parsing is in `SpokenSetParser`, which is pure and tested; this is the part
/// that hears it and writes it down.
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
        let known = templates.flatMap { $0.orderedExercises.map(\.name) }

        guard let log = SpokenSetParser.parse(spoken, knownExercises: known) else {
            return .result(dialog: "I didn't catch any sets in that.")
        }
        guard let exercise = log.exercise else {
            return .result(dialog: "Which lift was that?")
        }
        guard !log.reps.isEmpty else {
            return .result(dialog: "How many reps?")
        }

        let planned = templates.flatMap(\.orderedExercises).first {
            $0.name.caseInsensitiveCompare(exercise) == .orderedSame
        }
        let session = WorkoutSession.today(in: context, named: planned?.template?.name)
        let startingOrder = session.sets.count

        for (offset, reps) in log.reps.enumerated() {
            let set = LoggedSet(
                exerciseName: planned?.name ?? exercise,
                muscleGroup: planned?.muscleGroup ?? .core,
                load: log.load ?? planned?.workingWeight ?? 0,
                reps: reps,
                rir: log.rir ?? 2,
                order: startingOrder + offset,
                feel: log.feel)
            set.session = session
            context.insert(set)
        }
        try? context.save()

        return .result(dialog: IntentDialog(stringLiteral: Self.confirmation(log, exercise: exercise)))
    }

    /// Reads back what was understood, not what was said. Hearing "three sets, felt
    /// heavy" is how somebody catches a misparse without opening the app.
    private static func confirmation(_ log: SpokenSetLog, exercise: String) -> String {
        // The reps are the thing worth reading back: "1 set of bench" tells somebody
        // nothing about whether it heard them right.
        let sets: String
        if let first = log.reps.first, log.reps.allSatisfy({ $0 == first }) {
            sets = "\(Copy.count(log.reps.count, "set")) of \(first)"
        } else {
            sets = log.reps.map(String.init).joined(separator: ", ")
        }
        var parts = ["\(sets) on \(exercise)"]
        if let load = log.load {
            parts.append("at \(load.formatted(.number.precision(.fractionLength(0)))) lb")
        }
        if let rir = log.rir {
            parts.append(rir == 0 ? "to failure" : "\(rir) in reserve")
        }
        if let feel = log.feel { parts.append("felt \(feel.rawValue)") }
        return "Got it. " + parts.joined(separator: ", ") + "."
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
