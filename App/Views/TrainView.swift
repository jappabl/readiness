import SwiftUI
import SwiftData

struct TrainView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @State private var liveSession: WorkoutSession?
    @State private var editingTemplate: WorkoutTemplate?

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    programSection
                    historySection
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.vertical, 8)
                .padding(.bottom, 88)
            }
        }
        .navigationTitle("Train")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let template = WorkoutTemplate(name: "New session", order: templates.count)
                    context.insert(template)
                    try? context.save()
                    editingTemplate = template
                } label: { Label("New template", systemImage: "plus") }
            }
        }
        .fullScreenCover(item: $liveSession) { LiveWorkoutView(session: $0) }
        .sheet(item: $editingTemplate) { TemplateEditorView(template: $0) }
    }

    private var programSection: some View {
        VStack(alignment: .leading, spacing: Tokens.cardGap) {
            Text("Program").sectionHeader()
            if templates.isEmpty {
                Text("No templates yet. Add one to start training.")
                    .font(.subheadline).foregroundStyle(Tokens.textSecondary).card()
            }
            ForEach(templates) { template in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(template.name)
                            .font(.body.weight(.semibold)).foregroundStyle(Tokens.textPrimary)
                        Spacer()
                        Button("Edit") { editingTemplate = template }
                            .font(.footnote).tint(Tokens.accent)
                    }
                    ForEach(template.orderedExercises) { exercise in
                        HStack {
                            Text(exercise.name).font(.subheadline)
                                .foregroundStyle(Tokens.textSecondary)
                            Spacer()
                            Text("\(exercise.targetSets)×\(exercise.targetReps) @ \(Int(exercise.workingWeight)) lb")
                                .font(.subheadline).monospacedDigit()
                                .foregroundStyle(Tokens.textSecondary)
                        }
                    }
                    Button {
                        let session = WorkoutSession(date: Calendar.current.startOfDay(for: Date()),
                                                     templateName: template.name)
                        context.insert(session)
                        try? context.save()
                        liveSession = session
                    } label: {
                        Text("Start session")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Tokens.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(Tokens.accent)
                    .disabled(template.exercises.isEmpty)
                }
                .card()
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: Tokens.cardGap) {
            Text("History").sectionHeader()
            if sessions.isEmpty {
                Text("Completed sessions show up here.")
                    .font(.subheadline).foregroundStyle(Tokens.textSecondary).card()
            }
            ForEach(sessions.prefix(20)) { session in
                let load = session.load
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(session.date, format: .dateTime.month(.abbreviated).day())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Tokens.textPrimary)
                        Spacer()
                        Text(session.templateName).font(.footnote)
                            .foregroundStyle(Tokens.textSecondary)
                    }
                    Text("\(Int(load.volumeLoad)) lb volume · "
                         + "\(load.hardSetsByMuscle.values.reduce(0, +)) hard sets"
                         + (session.sessionRPE > 0
                            ? " · sRPE \(session.sessionRPE.formatted(.number.precision(.fractionLength(0))))"
                            : ""))
                        .qualifier()
                    if !session.isComplete {
                        Text("In progress").font(.caption).foregroundStyle(Tokens.accent)
                    }
                }
                .card()
            }
        }
    }
}

// MARK: - Live workout

/// Fast enough to replace a dedicated logger: the common case is one tap per set.
struct LiveWorkoutView: View {
    @Bindable var session: WorkoutSession

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]

    @State private var exerciseIndex = 0
    @State private var restRemaining = 0
    @State private var restTimer: Timer?
    @State private var showingFinish = false

    private var template: WorkoutTemplate? {
        templates.first { $0.name == session.templateName }
    }
    private var exercises: [TemplateExercise] { template?.orderedExercises ?? [] }
    private var current: TemplateExercise? {
        exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil
    }
    private var setsLogged: Int {
        guard let current else { return 0 }
        return session.sets.filter { $0.exerciseName == current.name && !$0.isWarmup }.count
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                if let current {
                    workingView(current)
                } else {
                    ContentUnavailableView("Nothing to log", systemImage: "dumbbell",
                                           description: Text("This template has no exercises."))
                }
            }
            .navigationTitle(session.templateName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { stopTimer(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { showingFinish = true }.font(.body.weight(.semibold))
                }
            }
            .sheet(isPresented: $showingFinish) {
                FinishSessionView(session: session) { stopTimer(); dismiss() }
            }
        }
    }

    /// Only what is needed for the set in front of you.
    private func workingView(_ exercise: TemplateExercise) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text(exercise.name)
                    .font(.system(.title2, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
                Text("Set \(setsLogged + 1) of \(exercise.targetSets)")
                    .qualifier()
            }
            .padding(.top, 12)

            VStack(spacing: 2) {
                Text("\(Int(lastLoad(for: exercise)))")
                    .font(.system(size: 64, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.accent)
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text("lb × \(lastReps(for: exercise)) reps").qualifier()
            }

            if restRemaining > 0 {
                Text("Rest \(restRemaining)s")
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Tokens.accent)
                    .accessibilityLabel("Resting, \(restRemaining) seconds remaining")
            }

            Button {
                logSet(exercise)
            } label: {
                Text("Log set")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Tokens.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent).tint(Tokens.accent)

            HStack(spacing: 10) {
                Button("Missed reps") { logSet(exercise, repsDelta: -2) }
                    .buttonStyle(.bordered).tint(Tokens.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                Button("Next exercise") {
                    exerciseIndex = min(exerciseIndex + 1, max(0, exercises.count - 1))
                }
                .buttonStyle(.bordered).tint(Tokens.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(exerciseIndex >= exercises.count - 1)
            }

            loggedSoFar

            Spacer()
        }
        .padding(.horizontal, Tokens.screenMargin)
    }

    private var loggedSoFar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !session.orderedSets.isEmpty {
                Text("Logged").sectionHeader()
                ForEach(session.orderedSets.suffix(4)) { set in
                    HStack {
                        Text(set.exerciseName).font(.footnote)
                            .foregroundStyle(Tokens.textSecondary)
                        Spacer()
                        Text("\(Int(set.load)) × \(set.reps) · RIR \(set.rir)")
                            .font(.footnote).monospacedDigit()
                            .foregroundStyle(Tokens.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lastLoad(for exercise: TemplateExercise) -> Double {
        session.sets.last { $0.exerciseName == exercise.name }?.load ?? exercise.workingWeight
    }
    private func lastReps(for exercise: TemplateExercise) -> Int {
        session.sets.last { $0.exerciseName == exercise.name }?.reps ?? exercise.targetReps
    }

    private func logSet(_ exercise: TemplateExercise, repsDelta: Int = 0) {
        let set = LoggedSet(exerciseName: exercise.name,
                            muscleGroup: exercise.muscleGroup,
                            load: lastLoad(for: exercise),
                            reps: max(0, lastReps(for: exercise) + repsDelta),
                            rir: exercise.targetRIR,
                            order: session.sets.count)
        set.session = session
        session.sets.append(set)
        try? context.save()
        startRest(seconds: exercise.restSeconds)

        if setsLogged >= exercise.targetSets, exerciseIndex < exercises.count - 1 {
            exerciseIndex += 1
        }
    }

    private func startRest(seconds: Int) {
        stopTimer()
        restRemaining = seconds
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            Task { @MainActor in
                if restRemaining > 0 { restRemaining -= 1 } else { timer.invalidate() }
            }
        }
    }

    private func stopTimer() {
        restTimer?.invalidate()
        restTimer = nil
        restRemaining = 0
    }
}

struct FinishSessionView: View {
    @Bindable var session: WorkoutSession
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var rpe: Double = 7

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Session RPE")
                            Spacer()
                            Text(rpe.formatted(.number.precision(.fractionLength(0))))
                                .monospacedDigit().foregroundStyle(Tokens.textSecondary)
                        }
                        Slider(value: $rpe, in: 1...10, step: 1).tint(Tokens.accent)
                    }
                } footer: {
                    Text("How hard the whole session felt, 1 to 10. This feeds tomorrow's load calculation.")
                }
                Section {
                    let load = session.load
                    LabeledContent("Volume", value: "\(Int(load.volumeLoad)) lb")
                    LabeledContent("Hard sets", value: "\(load.hardSetsByMuscle.values.reduce(0, +))")
                    LabeledContent("Near failure",
                                   value: load.closeToFailureShare.formatted(.percent.precision(.fractionLength(0))))
                }
            }
            .navigationTitle("Finish session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        session.sessionRPE = rpe
                        session.isComplete = true
                        session.finishedAt = Date()
                        try? context.save()
                        dismiss()
                        onDone()
                    }
                    .font(.body.weight(.semibold))
                }
            }
        }
    }
}
