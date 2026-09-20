import SwiftUI
import SwiftData

/// Whether the user has ever held Jett's face. Until they have, the logging screen
/// says the gesture exists once — a hold nobody is told about is a hold nobody uses,
/// and onboarding is the wrong place to teach it, because there is nothing to log yet.
enum HoldToTalk {
    private static let key = "dictation.heldJett"
    static var discovered: Bool { UserDefaults.standard.bool(forKey: key) }
    static func markDiscovered() { UserDefaults.standard.set(true, forKey: key) }
}

/// Speaking a set, wherever you are.
///
/// Two doors into the same machinery. Inside a live workout the microphone sits next to
/// the Log button, because that is where somebody already is between sets. Everywhere
/// else, holding Jett's face opens `DictationSheet` — which has no screen context to
/// work from, so it has to do more work to know which lift was meant.
///
/// Neither writes anything off a transcript alone. What was understood is always shown
/// first: a misheard set is worse than a typed one, because nobody catches it later.

// MARK: - The pieces both doors use

/// Words as they arrive, so it is obvious the phone is hearing you.
struct ListeningRow: View {
    let transcript: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .foregroundStyle(Tokens.strainLow)
                .symbolEffect(.variableColor.iterative, isActive: true)
            Text(transcript.isEmpty ? "Listening" : transcript)
                .font(.subheadline)
                .foregroundStyle(transcript.isEmpty ? Tokens.textSecondary : Tokens.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// What it was understood to mean, and the two ways out.
struct SpokenSetCard: View {
    let resolution: SpokenSetResolver.Resolution
    let metric: Bool
    var log: () -> Void
    var discard: () -> Void

    var body: some View {
        ListCard {
            VStack(alignment: .leading, spacing: 4) {
                Text(SpokenSetWriter.understood(resolution, metric: metric))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                // The raw words underneath: the only way to tell a misparse from a
                // mishearing, and they are different problems.
                Text("“\(resolution.transcript)”")
                    .font(.caption)
                    .foregroundStyle(Tokens.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            Divider().overlay(Tokens.hairline)
            HStack(spacing: 0) {
                Button("Log it", action: log)
                    .font(.subheadline.weight(.semibold)).tint(Tokens.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                Divider().overlay(Tokens.hairline).frame(height: 28)
                Button("Discard", action: discard)
                    .font(.subheadline).tint(Tokens.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }
}

// MARK: - The door from anywhere

/// Held Jett's face from any screen.
///
/// Starts listening on appear, because holding the face already said what you wanted —
/// making somebody then tap a second button would be a worse version of tapping once.
struct DictationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query private var profiles: [UserProfile]

    @State private var dictation = Dictation()
    @State private var heard: SpokenSetResolver.Resolution?
    @State private var problem: String?
    /// Said a set but never named a lift, and nothing was open to assume. Rather than
    /// refuse, hold the words and ask which one.
    @State private var awaitingExercise: String?

    private var metric: Bool { profiles.first?.unitsAreMetric ?? model.onboarding.unitsAreMetric }
    private var programme: [TemplateExercise] { templates.flatMap(\.orderedExercises) }

    /// The sheet is exactly as tall as what is in it, and grows as the state changes —
    /// listening, then what was understood, then sometimes a list of lifts. A fixed
    /// detent would be half empty for the first of those and cramped for the last.
    @State private var contentHeight: CGFloat = 160

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(.horizontal, Tokens.screenMargin)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear.onChange(of: proxy.size.height, initial: true) { _, height in
                    contentHeight = height
                }
            }
        }
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tokens.canvas)
        .animation(.snappy(duration: 0.28), value: contentHeight)
        .tint(Tokens.accent)
        .task {
            HoldToTalk.markDiscovered()
            await dictation.start()
        }
        .onDisappear { dictation.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if case let .unavailable(reason) = dictation.status {
            Text(reason).font(.subheadline).foregroundStyle(Tokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if dictation.isListening {
            ListeningRow(transcript: dictation.transcript)
            if dictation.transcript.isEmpty {
                Text("“Bench press, 225 for 8, felt heavy.”")
                    .font(.caption).foregroundStyle(Tokens.textSecondary)
            }
            PrimaryButton(label: "Done", symbol: "stop.fill", tint: Tokens.strainLow) {
                Haptics.decided()
                finish()
            }
        } else if let heard {
            SpokenSetCard(resolution: heard, metric: metric,
                          log: { commit(heard) },
                          discard: { self.heard = nil; restart() })
        } else if let awaitingExercise {
            liftPicker(for: awaitingExercise)
        } else if let problem {
            Text(problem).font(.subheadline).foregroundStyle(Tokens.textPrimary)
            PrimaryButton(label: "Try again", symbol: "mic.fill", tint: Tokens.strainLow) {
                restart()
            }
        } else {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    /// The reps were heard; only the lift is missing. Asking somebody to say the whole
    /// sentence again to add one word is the wrong trade.
    private func liftPicker(for spoken: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which lift was that?")
                .font(.headline).foregroundStyle(Tokens.textPrimary)
            Text("“\(spoken)”")
                .font(.caption).foregroundStyle(Tokens.textSecondary)
            ListCard {
                ForEach(Array(uniqueProgramme.enumerated()), id: \.element.id) { index, exercise in
                    if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                    Button {
                        awaitingExercise = nil
                        resolve(spoken, current: exercise.plannedExercise)
                    } label: {
                        HStack {
                            Text(exercise.name).foregroundStyle(Tokens.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote).foregroundStyle(Tokens.textSecondary)
                        }
                        .padding(14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// One row per lift, not one per template: a lift in three splits is still one lift.
    private var uniqueProgramme: [TemplateExercise] {
        var seen = Set<String>()
        return programme.filter { seen.insert($0.name.lowercased()).inserted }
    }

    // MARK: - Hearing it

    private func restart() {
        heard = nil
        problem = nil
        awaitingExercise = nil
        dictation.reset()
        Task { await dictation.start() }
    }

    private func finish() {
        resolve(dictation.stop(), current: lastLoggedExercise)
    }

    /// With no screen to read, the best guess at "225 for 8" is whatever they were last
    /// doing today. A set said mid-session almost always belongs to the lift in hand.
    private var lastLoggedExercise: PlannedExercise? {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        guard let today = sessions.first(where: {
            Calendar.current.isDateInToday($0.date) && !$0.isComplete
        }), let last = today.orderedSets.last else { return nil }
        return programme.first {
            $0.name.caseInsensitiveCompare(last.exerciseName) == .orderedSame
        }?.plannedExercise
    }

    private func resolve(_ spoken: String, current: PlannedExercise?) {
        switch SpokenSetResolver.resolve(spoken, current: current,
                                         programme: programme.map(\.plannedExercise),
                                         unitsAreMetric: metric) {
        case .ready(let resolution):
            heard = resolution
        case .needsExercise:
            awaitingExercise = spoken
        case .needsReps:
            problem = "I caught that, but not how many reps."
        case .heardNothing:
            problem = spoken.isEmpty ? "I didn’t hear anything."
                                     : "I didn’t catch a set in “\(spoken)”."
        }
    }

    private func commit(_ resolution: SpokenSetResolver.Resolution) {
        let planned = programme.first {
            $0.name.caseInsensitiveCompare(resolution.exercise.name) == .orderedSame
        }
        let session = WorkoutSession.today(in: context, named: planned?.template?.name)
        SpokenSetWriter.write(resolution, muscleGroup: planned?.muscleGroup ?? .core,
                              into: session, in: context)
        Haptics.committed()
        dismiss()
    }
}
