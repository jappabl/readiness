import SwiftUI
import SwiftData

struct TrainView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var profiles: [UserProfile]
    @State private var liveSession: WorkoutSession?
    @State private var editingTemplate: WorkoutTemplate?
    @State private var creatingSession = false
    @State private var choosingSplit = false
    @State private var expandedTemplates: Set<PersistentIdentifier> = []

    private var metric: Bool { profiles.first?.unitsAreMetric ?? model.onboarding.unitsAreMetric }

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) { program; history }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.top, 4).padding(.bottom, 16)
            }
        }
        .navigationTitle("Train")
        .toolbarBackground(Tokens.canvas, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Create session", systemImage: "plus") { creatingSession = true }
                    Button("Choose starter split", systemImage: "square.grid.2x2") { choosingSplit = true }
                } label: { Image(systemName: "plus") }
                    .tint(Tokens.textPrimary).accessibilityLabel("Add to your split")
            }
        }
        .fullScreenCover(item: $liveSession) { LiveWorkoutView(session: $0) }
        .sheet(item: $editingTemplate) { TemplateEditorView(template: $0) }
        .sheet(isPresented: $creatingSession) {
            TemplateEditorView(onSave: { model.selectToday($0) })
        }
        .sheet(isPresented: $choosingSplit) { NavigationStack { ProgramSetupView() } }
    }

    private var program: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your split").sectionHeading()
            if templates.isEmpty {
                ListCard {
                    AccessoryRow(symbol: "dumbbell", label: "Choose a starter split") { choosingSplit = true }
                    Divider().overlay(Tokens.hairline)
                    AccessoryRow(symbol: "plus", label: "Create a session") { creatingSession = true }
                }
            }
            ForEach(templates) { template in
                let expanded = expandedTemplates.contains(template.persistentModelID)
                ListCard {
                    Button {
                        if expanded { expandedTemplates.remove(template.persistentModelID) }
                        else { expandedTemplates.insert(template.persistentModelID) }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(template.name).font(.headline).foregroundStyle(Tokens.textPrimary)
                                Text(Copy.count(template.exercises.count, "exercise"))
                                    .font(.subheadline).foregroundStyle(Tokens.textSecondary)
                            }
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold)).foregroundStyle(Tokens.textSecondary)
                        }
                        .frame(minHeight: 44).padding(14).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if expanded {
                        ForEach(template.orderedExercises) { exercise in
                            Divider().overlay(Tokens.hairline).padding(.leading, 14)
                            FieldRow(label: exercise.name) {
                                Text("\(exercise.targetSets) × \(exercise.targetReps)" + loadText(exercise.workingWeight))
                                    .monospacedDigit()
                            }
                        }
                    }
                    Divider().overlay(Tokens.hairline)
                    HStack {
                        Button("Edit") { editingTemplate = template }
                        Spacer()
                        Button("Use today") {
                            model.selectToday(template)
                            Haptics.decided()
                            Task { await model.refresh() }
                        }
                        .disabled(template.exercises.isEmpty)
                        Button("Start") {
                            model.selectToday(template)
                            liveSession = WorkoutSession.today(in: context, named: template.name)
                        }
                        .fontWeight(.semibold).padding(.leading, 12)
                        .disabled(template.exercises.isEmpty)
                    }
                    .font(.subheadline).tint(Tokens.accent)
                    .frame(minHeight: 44).padding(.horizontal, 14)
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History").sectionHeading()
            if sessions.isEmpty {
                Text("Your completed sessions will appear here.")
                    .font(.subheadline).foregroundStyle(Tokens.textSecondary)
            }
            ForEach(sessions.prefix(20)) { session in
                HStack(spacing: 12) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .foregroundStyle(Tokens.textSecondary).frame(width: 28)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(session.templateName).font(.body.weight(.medium)).foregroundStyle(Tokens.textPrimary)
                        Text(Copy.count(session.sets.count, "set") + (session.isComplete ? "" : " · In progress"))
                            .font(.subheadline).foregroundStyle(Tokens.textSecondary)
                    }
                    Spacer()
                    Text(session.date, format: .dateTime.month(.abbreviated).day())
                        .font(.caption).foregroundStyle(Tokens.textSecondary)
                }
                .bevelCard(padding: 12)
            }
        }
    }

    private func loadText(_ pounds: Double) -> String {
        guard pounds > 0 else { return "" }
        let value = metric ? pounds / 2.2046226218 : pounds
        return " · \(value.formatted(.number.precision(.fractionLength(0...1)))) \(metric ? "kg" : "lb")"
    }
}

// MARK: - Live workout

struct LiveWorkoutView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query private var profiles: [UserProfile]
    @State private var exerciseIndex = 0
    @State private var restRemaining = 0
    @State private var restTimer: Timer?
    @State private var showingFinish = false
    @State private var weight = ""
    @State private var reps = 8
    @State private var rir = 2
    @State private var saveError = false

    private var metric: Bool { profiles.first?.unitsAreMetric ?? model.onboarding.unitsAreMetric }
    private var unit: String { metric ? "kg" : "lb" }
    private var template: WorkoutTemplate? { templates.first { $0.name == session.templateName } }
    private var exercises: [TemplateExercise] { template?.orderedExercises ?? [] }
    private var current: TemplateExercise? { exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil }
    private var setsLogged: Int {
        guard let current else { return 0 }
        return session.sets.filter { $0.exerciseName == current.name && !$0.isWarmup }.count
    }
    private var enteredLoad: Double? {
        let trimmed = weight.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalized = trimmed.replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        return metric ? value * 2.2046226218 : value
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                if let current {
                    ScrollView { working(current) }
                        .scrollDismissesKeyboard(.interactively)
                } else {
                    ContentUnavailableView("No exercises", systemImage: "dumbbell",
                                           description: Text("Add exercises to this session before you start."))
                }
            }
            .navigationTitle(session.templateName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { showingFinish = true }.fontWeight(.semibold)
                        .disabled(session.sets.isEmpty)
                }
            }
            .tint(Tokens.accent)
            .onAppear(perform: prepareSet)
            .onChange(of: exerciseIndex) { _, _ in prepareSet() }
            .onDisappear(perform: stopTimer)
            .sheet(isPresented: $showingFinish) {
                FinishSessionView(session: session) { stopTimer(); dismiss() }
            }
            .alert("Set wasn’t saved", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: { Text("Please try logging the set again.") }
        }
    }

    private func working(_ exercise: TemplateExercise) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.name).font(.title2.weight(.bold)).foregroundStyle(Tokens.textPrimary)
                Text(setsLogged < exercise.targetSets ? "Set \(setsLogged + 1) of \(exercise.targetSets)" : "Set \(setsLogged + 1)")
                    .font(.subheadline).foregroundStyle(Tokens.textSecondary)
            }
            ListCard {
                FieldRow(label: "Weight (\(unit))") {
                    TextField("Enter weight", text: $weight)
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                        .accessibilityLabel("Set weight in \(metric ? "kilograms" : "pounds")")
                }
                Divider().overlay(Tokens.hairline).padding(.leading, 14)
                Stepper(value: $reps, in: 1...50) { LabeledContent("Reps", value: "\(reps)") }
                    .monospacedDigit().padding(14)
                Divider().overlay(Tokens.hairline).padding(.leading, 14)
                Stepper(value: $rir, in: 0...6) { LabeledContent("Reps in reserve", value: "\(rir)") }
                    .monospacedDigit().padding(14)
            }
            if weight.isEmpty {
                Text("Enter the weight you used, or 0 for no added load.")
                    .font(.caption).foregroundStyle(Tokens.textSecondary)
            }
            if restRemaining > 0 {
                HStack {
                    Label("Rest \(restRemaining)s", systemImage: "timer")
                        .font(.body.monospacedDigit()).foregroundStyle(Tokens.textSecondary)
                    Spacer()
                    Button("Skip rest", action: stopTimer).font(.subheadline)
                }
                .frame(minHeight: 44)
            }
            PrimaryButton(label: "Log set", tint: Tokens.strainLow, enabled: enteredLoad != nil) { logSet(exercise) }
            HStack {
                Button("Previous exercise") { exerciseIndex -= 1 }
                    .disabled(exerciseIndex == 0)
                Spacer()
                Button("Next exercise") { exerciseIndex += 1 }
                    .disabled(exerciseIndex >= exercises.count - 1)
            }
            .font(.subheadline).frame(minHeight: 44)
            if !session.orderedSets.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Logged sets").font(.headline)
                    ListCard {
                        ForEach(Array(session.orderedSets.suffix(4).enumerated()), id: \.element.id) { index, set in
                            if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                            FieldRow(label: set.exerciseName) {
                                Text("\(displayLoad(set.load)) \(unit) × \(set.reps)").monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Tokens.screenMargin).padding(.vertical, 16)
    }

    private func prepareSet() {
        guard let current else { return }
        let last = session.orderedSets.last { $0.exerciseName == current.name }
        if let last { weight = displayLoad(last.load) }
        else if current.workingWeight > 0 || current.increment == 0 { weight = displayLoad(current.workingWeight) }
        else { weight = "" }
        reps = last?.reps ?? current.targetReps
        rir = last?.rir ?? current.targetRIR
    }

    private func displayLoad(_ pounds: Double) -> String {
        (metric ? pounds / 2.2046226218 : pounds).formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    private func logSet(_ exercise: TemplateExercise) {
        guard let load = enteredLoad else { return }
        let set = LoggedSet(exerciseName: exercise.name, muscleGroup: exercise.muscleGroup,
                            load: load, reps: reps, rir: rir, order: session.sets.count)
        set.session = session
        session.sets.append(set)
        do {
            try context.save()
            Haptics.committed()
            startRest(seconds: exercise.restSeconds)
            if setsLogged >= exercise.targetSets, exerciseIndex < exercises.count - 1 { exerciseIndex += 1 }
        } catch {
            session.sets.removeAll { $0 === set }
            context.delete(set)
            saveError = true
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
                } else { timer.invalidate() }
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
    @Query private var profiles: [UserProfile]
    @State private var rpe: Double = 7
    @State private var saveError = false

    private var metric: Bool { profiles.first?.unitsAreMetric ?? false }

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        let load = session.load
                        HStack(spacing: Tokens.cardGap) {
                            StatCard(symbol: "scalemass", label: "Volume",
                                     value: "\(Int(metric ? load.volumeLoad / 2.2046226218 : load.volumeLoad))", unit: metric ? "kg" : "lb")
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
                            let previousRPE = session.sessionRPE
                            let previousFinish = session.finishedAt
                            session.sessionRPE = rpe
                            session.isComplete = true
                            session.finishedAt = Date()
                            do {
                                try context.save()
                                Haptics.committed()
                                dismiss(); onDone()
                            } catch {
                                session.sessionRPE = previousRPE
                                session.isComplete = false
                                session.finishedAt = previousFinish
                                saveError = true
                            }
                        }
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.vertical, 12)
                }
            }
            .alert("Session wasn’t saved", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: { Text("Your logged sets are still here. Please try saving again.") }
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
