import SwiftUI
import SwiftData

/// Saved workouts and a small set of starters share one selection path.
struct ProgramSetupView: View {
    var onSelected: ((WorkoutTemplate) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @State private var creatingSession = false
    @State private var createdSession: WorkoutTemplate?
    @State private var saveError: String?

    var body: some View {
        List {
            if !templates.isEmpty {
                Section("Your sessions") {
                    ForEach(templates) { template in
                        Button { Haptics.selected(); select(template) } label: {
                            choice(name: template.name,
                                   detail: Copy.count(template.exercises.count, "exercise"),
                                   symbol: "dumbbell")
                        }
                        .disabled(template.exercises.isEmpty)
                    }
                }
            }
            Section {
                ForEach(starters, id: \.name) { starter in
                    Button { Haptics.decided(); install(starter) } label: {
                        choice(name: starter.name, detail: splitDetail(starter),
                               symbol: "figure.strengthtraining.traditional")
                    }
                }
                if starters.isEmpty {
                    Text("No starter matches your current limits.")
                        .foregroundStyle(Tokens.textSecondary)
                }
            } header: {
                Text("Starter splits")
            } footer: {
                Text("Matched to your equipment and limits. Add your own weights when you edit.")
            }
            Section {
                Button { Haptics.light(); creatingSession = true } label: {
                    Label("Create a session", systemImage: "plus")
                        .frame(minHeight: 32)
                }
            }
        }
        .tint(Tokens.accent)
        .navigationTitle(templates.isEmpty ? "Choose a split" : "Choose workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(isPresented: $creatingSession, onDismiss: {
            if let createdSession {
                self.createdSession = nil
                select(createdSession)
            }
        }) {
            TemplateEditorView(onSave: { createdSession = $0 })
        }
        .alert("Couldn’t save the split", isPresented: Binding(
            get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: { Text(saveError ?? "Please try again.") }
    }

    private func choice(name: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Tokens.textSecondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.body.weight(.medium)).foregroundStyle(Tokens.textPrimary)
                Text(detail).font(.subheadline).foregroundStyle(Tokens.textSecondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(Tokens.textSecondary)
        }
        .frame(minHeight: 48).contentShape(Rectangle())
    }

    private var starters: [StarterPrograms.Split] {
        StarterPrograms.splits(experience: model.onboarding.experience ?? .new,
                               equipment: model.onboarding.equipment ?? .bodyweight,
                               limitations: model.trainingLimitations)
    }

    private func splitDetail(_ split: StarterPrograms.Split) -> String {
        if split.sessions.count == 1 {
            return Copy.count(split.sessions[0].exercises.count, "exercise") + " per session"
        }
        return split.sessions.map { "\($0.name): \($0.exercises.count) exercises" }.joined(separator: " · ")
    }

    private func select(_ template: WorkoutTemplate) {
        model.selectToday(template)
        onSelected?(template)
        dismiss()
        Task { await model.refresh() }
    }

    private func install(_ split: StarterPrograms.Split) {
        var installed: [WorkoutTemplate] = []
        var created: [WorkoutTemplate] = []
        for plan in split.sessions {
            // Reuse a matching starter without replacing its weights. A changed equipment
            // or limitation profile gets a newly filtered session, preserving the old one.
            if let existing = templates.first(where: {
                $0.name == plan.name && $0.orderedExercises.map(\.name) == plan.exercises.map(\.name)
            }) {
                installed.append(existing)
                continue
            }
            let name = availableName(plan.name)
            let template = WorkoutTemplate(name: name, order: (templates.map(\.order).max() ?? -1) + created.count + 1)
            context.insert(template)
            for (index, item) in plan.exercises.enumerated() {
                let exercise = TemplateExercise(name: item.name, muscleGroup: item.muscle,
                                                targetSets: plan.sets, targetReps: plan.reps,
                                                workingWeight: 0, increment: item.increment,
                                                targetRIR: plan.rir, order: index)
                exercise.template = template
                template.exercises.append(exercise)
            }
            installed.append(template)
            created.append(template)
        }
        do {
            try context.save()
            if let first = installed.first { select(first) }
        } catch {
            for template in created { context.delete(template) }
            saveError = "Your split wasn’t saved. Please try again."
        }
    }

    private func availableName(_ proposed: String) -> String {
        var name = proposed
        var suffix = 2
        while templates.contains(where: { $0.name == name }) {
            name = "\(proposed) \(suffix)"
            suffix += 1
        }
        return name
    }
}

/// Value drafts prevent cancelled edits or a cancelled new session from changing the plan.
struct TemplateEditorView: View {
    let template: WorkoutTemplate?
    var onSave: ((WorkoutTemplate) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Query private var profiles: [UserProfile]
    @Query private var templates: [WorkoutTemplate]
    @State private var name: String
    @State private var exercises: [TrainingExerciseDraft]
    @State private var showingDelete = false
    @State private var saveError: String?

    init(template: WorkoutTemplate? = nil, onSave: ((WorkoutTemplate) -> Void)? = nil) {
        self.template = template
        self.onSave = onSave
        _name = State(initialValue: template?.name ?? "")
        _exercises = State(initialValue: template?.orderedExercises.map(TrainingExerciseDraft.init) ?? [])
    }

    private var metric: Bool { profiles.first?.unitsAreMetric ?? model.onboarding.unitsAreMetric }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameIsTaken: Bool {
        templates.contains { $0.persistentModelID != template?.persistentModelID &&
            $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame }
    }
    private var canSave: Bool {
        !cleanName.isEmpty && !nameIsTaken && !exercises.isEmpty &&
        exercises.allSatisfy { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            $0.workingWeight.isFinite && $0.workingWeight >= 0 && $0.increment.isFinite && $0.increment >= 0 } &&
        Set(exercises.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count == exercises.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Session name", text: $name)
                    if nameIsTaken {
                        Text("You already have a session with this name.").font(.caption).foregroundStyle(Tokens.negative)
                    }
                } header: { Text("Session") }
                Section {
                    ForEach($exercises) { $exercise in
                        ExerciseEditorRow(exercise: $exercise, metric: metric)
                    }
                    .onDelete { exercises.remove(atOffsets: $0) }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        exercises.append(TrainingExerciseDraft())
                    } label: { Label("Add exercise", systemImage: "plus") }
                } header: { Text("Exercises") } footer: {
                    Text(exercises.isEmpty ? "Add the exercises you want in this session." : "Use a different name for each exercise. Zero weight means no added load.")
                }
                if template != nil {
                    Section {
                        Button("Delete session", role: .destructive) { showingDelete = true }
                    }
                }
            }
            .tint(Tokens.accent)
            .navigationTitle(template == nil ? "New session" : "Edit session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold).disabled(!canSave)
                }
                ToolbarItem(placement: .bottomBar) { if exercises.count > 1 { EditButton() } }
            }
            .confirmationDialog("Delete this session?", isPresented: $showingDelete, titleVisibility: .visible) {
                Button("Delete session", role: .destructive, action: delete)
            } message: { Text("Your logged workouts will stay in History.") }
            .alert("Couldn’t save", isPresented: Binding(
                get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                    Button("OK", role: .cancel) { saveError = nil }
                } message: { Text(saveError ?? "Please try again.") }
        }
    }

    private func save() {
        guard canSave else { return }
        let saved = template ?? WorkoutTemplate(name: cleanName, order: (templates.map(\.order).max() ?? -1) + 1)
        if template == nil { context.insert(saved) }
        saved.name = cleanName
        let retained = Set(exercises.compactMap { $0.source?.persistentModelID })
        for original in saved.exercises where !retained.contains(original.persistentModelID) {
            context.delete(original)
        }
        saved.exercises = exercises.enumerated().map { index, draft in
            let exercise = draft.source ?? TemplateExercise(name: draft.name, muscleGroup: draft.muscle,
                                                            workingWeight: 0)
            exercise.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            exercise.muscleGroupRaw = draft.muscle.rawValue
            exercise.targetSets = draft.sets
            exercise.targetReps = draft.reps
            exercise.workingWeight = draft.workingWeight
            exercise.increment = draft.increment
            exercise.targetRIR = draft.rir
            exercise.restSeconds = draft.rest
            exercise.order = index
            exercise.template = saved
            return exercise
        }
        do {
            try context.save()
            Haptics.committed()
            onSave?(saved)
            dismiss()
            Task { await model.refresh() }
        } catch {
            if template == nil { context.delete(saved) }
            saveError = "Your session wasn’t saved. Please try again."
        }
    }

    private func delete() {
        guard let template else { return }
        context.delete(template)
        do {
            try context.save()
            dismiss()
            Task { await model.refresh() }
        } catch { saveError = "Your session couldn’t be deleted. Please try again." }
    }
}

struct TrainingExerciseDraft: Identifiable {
    let id = UUID()
    var source: TemplateExercise?
    var name = ""
    var muscle: MuscleGroup = .chest
    var sets = 3
    var reps = 8
    var workingWeight = 0.0
    var increment = 0.0
    var rir = 2
    var rest = 120

    init() {}
    init(_ exercise: TemplateExercise) {
        source = exercise
        name = exercise.name
        muscle = exercise.muscleGroup
        sets = exercise.targetSets
        reps = exercise.targetReps
        workingWeight = exercise.workingWeight
        increment = exercise.increment
        rir = exercise.targetRIR
        rest = exercise.restSeconds
    }
}

struct ExerciseEditorRow: View {
    @Binding var exercise: TrainingExerciseDraft
    let metric: Bool
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            TextField("Exercise name", text: $exercise.name)
            Picker("Muscle group", selection: $exercise.muscle) {
                ForEach(MuscleGroup.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Stepper(value: $exercise.sets, in: 1...10) { LabeledContent("Sets", value: "\(exercise.sets)") }
            Stepper(value: $exercise.reps, in: 1...50) { LabeledContent("Reps", value: "\(exercise.reps)") }
            LabeledContent("Weight (\(metric ? "kg" : "lb"))") {
                TextField("Weight", value: displayWeight, format: .number.precision(.fractionLength(0...2)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                    .accessibilityLabel("Working weight in \(metric ? "kilograms" : "pounds")")
            }
            DisclosureGroup("Effort and rest") {
                Stepper(value: $exercise.rir, in: 0...6) { LabeledContent("Reps in reserve", value: "\(exercise.rir)") }
                Stepper(value: $exercise.rest, in: 30...420, step: 30) { LabeledContent("Rest", value: "\(exercise.rest)s") }
                LabeledContent("Weight increment (\(metric ? "kg" : "lb"))") {
                    TextField("Increment", value: displayIncrement, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
                        .accessibilityLabel("Weight increment in \(metric ? "kilograms" : "pounds")")
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name.isEmpty ? "New exercise" : exercise.name).foregroundStyle(Tokens.textPrimary)
                Text("\(exercise.sets) sets × \(exercise.reps) reps")
                    .font(.caption).monospacedDigit().foregroundStyle(Tokens.textSecondary)
            }
        }
        .onAppear { if exercise.name.isEmpty { expanded = true } }
    }

    private var displayWeight: Binding<Double> {
        Binding(get: { metric ? exercise.workingWeight / 2.2046226218 : exercise.workingWeight },
                set: { exercise.workingWeight = metric ? $0 * 2.2046226218 : $0 })
    }
    private var displayIncrement: Binding<Double> {
        Binding(get: { metric ? exercise.increment / 2.2046226218 : exercise.increment },
                set: { exercise.increment = metric ? $0 * 2.2046226218 : $0 })
    }
}
