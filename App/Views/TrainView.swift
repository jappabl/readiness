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
                VStack(alignment: .leading, spacing: 24) {
                    program
                    history
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Train")
        .toolbarBackground(Tokens.canvas, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let template = WorkoutTemplate(name: "New session", order: templates.count)
                    context.insert(template)
                    try? context.save()
                    editingTemplate = template
                } label: { Image(systemName: "plus").font(.system(size: 16, weight: .semibold)) }
                .tint(Tokens.textPrimary)
                .accessibilityLabel("New template")
            }
        }
        .fullScreenCover(item: $liveSession) { LiveWorkoutView(session: $0) }
        .sheet(item: $editingTemplate) { TemplateEditorView(template: $0) }
    }

    // MARK: - Program

    private var program: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Program").sectionHeading()
            if templates.isEmpty {
                Text("No templates yet")
                    .font(.system(size: 15)).foregroundStyle(Tokens.textSecondary)
                    .bevelCard()
            }
            ForEach(templates) { template in
                ListCard {
                    HStack {
                        Text(template.name)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Tokens.textPrimary)
                        Spacer()
                        Button("Edit") { editingTemplate = template }
                            .font(.system(size: 14)).tint(Tokens.accent)
                    }
                    .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

                    ForEach(template.orderedExercises) { exercise in
                        Divider().overlay(Tokens.hairline).padding(.leading, 14)
                        FieldRow(label: exercise.name) {
                            Text("\(exercise.targetSets)×\(exercise.targetReps) · \(Int(exercise.workingWeight)) lb")
                                .monospacedDigit()
                        }
                    }

                    Divider().overlay(Tokens.hairline)
                    AccessoryRow(symbol: "play.fill", label: "Start session",
                                 tint: template.exercises.isEmpty
                                     ? Tokens.textSecondary : Tokens.accent) {
                        guard !template.exercises.isEmpty else { return }
                        liveSession = WorkoutSession.today(in: context, named: template.name)
                    }
                }
            }
        }
    }

    // MARK: - History

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History").sectionHeading()
            if sessions.isEmpty {
                Text("No sessions yet")
                    .font(.system(size: 15)).foregroundStyle(Tokens.textSecondary)
                    .bevelCard()
            }
            ForEach(sessions.prefix(20)) { session in
                let load = session.load
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Tokens.strainLow.opacity(0.15))
                        .frame(width: 38, height: 38)
                        .overlay(Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 15)).foregroundStyle(Tokens.strainLow))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.templateName)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Tokens.textPrimary)
                        Text("\(Int(load.volumeLoad)) lb · "
                             + Copy.count(load.hardSetsByMuscle.values.reduce(0, +), "hard set"))
                            .font(.system(size: 13)).monospacedDigit()
                            .foregroundStyle(Tokens.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(session.date, format: .dateTime.month(.abbreviated).day())
                            .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                        if !session.isComplete {
                            Text("In progress").font(.system(size: 11))
                                .foregroundStyle(Tokens.accent)
                        }
                    }
                }
                .bevelCard(padding: 12)
            }
        }
    }
}

// MARK: - Live workout

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
                SkyBackground(signal: .strain)
                if let current { working(current) } else {
                    ContentUnavailableView("No exercises", systemImage: "dumbbell")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(session.templateName)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Tokens.textPrimary)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { stopTimer(); dismiss() }.tint(Tokens.textPrimary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { showingFinish = true }
                        .font(.system(size: 16, weight: .semibold)).tint(Tokens.accent)
                }
            }
            .sheet(isPresented: $showingFinish) {
                FinishSessionView(session: session) { stopTimer(); dismiss() }
            }
        }
    }

    private func working(_ exercise: TemplateExercise) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Tokens.textPrimary)
                // Past the plan there is no "of": extra sets are a real thing people do,
                // and now that sets arrive by voice it happens a lot.
                Text(setsLogged < exercise.targetSets
                     ? "Set \(setsLogged + 1) of \(exercise.targetSets)"
                     : "Set \(setsLogged + 1)")
                    .font(.system(size: 14)).foregroundStyle(Tokens.textSecondary)
            }
            .padding(.top, 10)

            ZStack {
                Circle().fill(Tokens.surface)
                    .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 6)
                VStack(spacing: -2) {
                    Text("\(Int(lastLoad(for: exercise)))")
                        .font(.system(size: 58, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Tokens.strainLow)
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("lb × \(lastReps(for: exercise))")
                        .font(.system(size: 14)).foregroundStyle(Tokens.textSecondary)
                }
                .padding(28)
            }
            .frame(width: 190, height: 190)

            if restRemaining > 0 {
                Text("Rest \(restRemaining)s")
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Tokens.strainLow)
                    .accessibilityLabel("Resting, \(restRemaining) seconds remaining")
            }

            PrimaryButton(label: "Log set", tint: Tokens.strainLow) { logSet(exercise) }

            HStack(spacing: 10) {
                secondary("Missed reps") { logSet(exercise, repsDelta: -2) }
                secondary("Next exercise") {
                    exerciseIndex = min(exerciseIndex + 1, max(0, exercises.count - 1))
                }
                .disabled(exerciseIndex >= exercises.count - 1)
            }

            if !session.orderedSets.isEmpty {
                ListCard {
                    ForEach(Array(session.orderedSets.suffix(4).enumerated()), id: \.element.id) { index, set in
                        if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                        FieldRow(label: set.exerciseName) {
                            HStack(spacing: 7) {
                                Text("\(Int(set.load)) × \(set.reps) · RIR \(set.rir)")
                                    .monospacedDigit()
                                // Only ever present on a set someone said out loud, and
                                // the only thing here no sensor could have told us.
                                if let feel = set.feel {
                                    Text(feel.displayName)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Tokens.accent)
                                        .padding(.horizontal, 7).padding(.vertical, 2)
                                        .background(Tokens.accent.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Tokens.screenMargin)
    }

    private func secondary(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Tokens.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func lastLoad(for exercise: TemplateExercise) -> Double {
        session.sets.last { $0.exerciseName == exercise.name }?.load ?? exercise.workingWeight
    }
    private func lastReps(for exercise: TemplateExercise) -> Int {
        session.sets.last { $0.exerciseName == exercise.name }?.reps ?? exercise.targetReps
    }

    private func logSet(_ exercise: TemplateExercise, repsDelta: Int = 0) {
        let set = LoggedSet(exerciseName: exercise.name, muscleGroup: exercise.muscleGroup,
                            load: lastLoad(for: exercise),
                            reps: max(0, lastReps(for: exercise) + repsDelta),
                            rir: exercise.targetRIR, order: session.sets.count)
        set.session = session
        session.sets.append(set)
        try? context.save()
        Haptics.committed()
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
                if restRemaining > 0 {
                    restRemaining -= 1
                    if restRemaining == 0 { Haptics.restOver() }
                } else {
                    timer.invalidate()
                }
            }
        }
    }

    private func stopTimer() {
        restTimer?.invalidate(); restTimer = nil; restRemaining = 0
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
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        let load = session.load
                        HStack(spacing: Tokens.cardGap) {
                            StatCard(symbol: "scalemass", label: "Volume",
                                     value: "\(Int(load.volumeLoad))", unit: "lb")
                            StatCard(symbol: "flame", label: "Hard sets",
                                     value: "\(load.hardSetsByMuscle.values.reduce(0, +))")
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Session RPE").microLabel()
                            HStack {
                                Text(rpe.formatted(.number.precision(.fractionLength(0))))
                                    .font(.system(size: 34, weight: .semibold)).monospacedDigit()
                                    .foregroundStyle(Tokens.strainLow)
                                Spacer()
                                Text("1 to 10")
                                    .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                            }
                            Slider(value: $rpe, in: 1...10, step: 1).tint(Tokens.strainLow)
                        }
                        .bevelCard()

                        PrimaryButton(label: "Save session", tint: Tokens.strainLow) {
                            Haptics.committed()
                            session.sessionRPE = rpe
                            session.isComplete = true
                            session.finishedAt = Date()
                            try? context.save()
                            dismiss(); onDone()
                        }
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Finish session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }.tint(Tokens.textPrimary)
                }
            }
        }
    }
}
