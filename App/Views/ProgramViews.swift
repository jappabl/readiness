import SwiftUI
import SwiftData

/// Saved workouts and a small set of starters share one selection path.
struct ProgramSetupView: View {
    var onSelected: ((WorkoutTemplate) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query private var profiles: [UserProfile]
    @State private var creatingSession = false
    @State private var createdSession: WorkoutTemplate?
    @State private var saveError: String?

    var body: some View {
        List {
            if !mine.isEmpty {
                Section("Your sessions") {
                    ForEach(mine) { template in
                        Button { Haptics.selected(); select(template) } label: {
                            choice(name: template.name,
                                   detail: Copy.count(template.exercises.count, "exercise"))
                        }
                        .disabled(template.exercises.isEmpty)
                    }
                }
            }
            Section {
                ForEach(starters, id: \.name) { starter in
                    Button { Haptics.decided(); install(starter) } label: {
                        choice(name: starter.name, detail: splitDetail(starter))
                    }
                }
                if starters.isEmpty {
                    Text("No starter matches your current limits.")
                        .foregroundStyle(Tokens.textSecondary)
                }
            } header: {
                Text("Starter splits")
            }
            Section {
                Button { Haptics.light(); creatingSession = true } label: {
                    Label("Create a session", systemImage: "plus")
                        .frame(minHeight: 32)
                }
            }
        }
        .tint(Tokens.accent)
        .navigationTitle(mine.isEmpty ? "Choose a split" : "Choose workout")
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

    private func choice(name: String, detail: String) -> some View {
        HStack(spacing: 12) {
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

    /// The sessions in the split being run, which is what "your sessions" means once
    /// more than one split exists.
    private var mine: [WorkoutTemplate] {
        let stored = profiles.first?.activeSplit ?? ""
        let available = Splits.names(in: templates)
        let active = available.contains(stored) ? stored : (available.first ?? "")
        return templates.filter { $0.splitName == active }
    }

    private var starters: [StarterPrograms.Split] {
        StarterPrograms.splits(experience: model.onboarding.experience ?? .new,
                               equipment: model.onboarding.equipment ?? .bodyweight,
                               limitations: model.trainingLimitations,
                               hasBar: model.onboarding.hasPullUpBar ?? true)
    }

    /// How many days it asks for, and nothing else. It used to name every session and
    /// count its exercises, which wrapped to three lines and repeated the title back:
    /// the row for Push / pull / legs read "Push: 6 exercises · Pull: 6 exercises ·
    /// Legs: 6 exercises". The sessions are one tap away; the number of days is the
    /// thing somebody is actually choosing between.
    private func splitDetail(_ split: StarterPrograms.Split) -> String {
        Copy.count(split.sessions.count, "day") + " a week"
    }

    private func select(_ template: WorkoutTemplate) {
        model.selectToday(template)
        onSelected?(template)
        dismiss()
        Task { await model.refresh() }
    }

    /// Adopting a split puts its sessions under its own name and switches to it.
    ///
    /// It used to append them to the flat list, so a week of trying push/pull/legs left
    /// somebody with eight sessions and no way back to the four they wrote themselves.
    private func install(_ split: StarterPrograms.Split) {
        var installed: [WorkoutTemplate] = []
        var created: [WorkoutTemplate] = []
        let already = templates.filter { $0.splitName == split.name }
        for plan in split.sessions {
            // Reuse a matching starter without replacing its weights. A changed equipment
            // or limitation profile gets a newly filtered session, preserving the old one.
            // Only within this split: a session of the same name in another one belongs
            // to that one, and borrowing it would leave this split a session short.
            if let existing = already.first(where: {
                $0.name == plan.name && $0.orderedExercises.map(\.name) == plan.exercises.map(\.name)
            }) {
                installed.append(existing)
                continue
            }
            let name = availableName(plan.name, in: split.name)
            let template = WorkoutTemplate(name: name,
                                           order: (templates.map(\.order).max() ?? -1) + created.count + 1,
                                           splitName: split.name)
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
            profiles.first?.activeSplit = split.name
            if let first = installed.first { select(first) }
        } catch {
            for template in created { context.delete(template) }
            saveError = "Your split wasn’t saved. Please try again."
        }
    }

    /// Unique inside its own split. Globally unique would rename the Upper of a second
    /// split to "Upper 2" for no reason anybody looking at one split could see.
    private func availableName(_ proposed: String, in split: String) -> String {
        var name = proposed
        var suffix = 2
        while templates.contains(where: { $0.splitName == split && $0.name == name }) {
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
    /// Which row asked to swap. One sheet for the whole form rather than one per row:
    /// a sheet modifier on every row means every row tries to present at once, and
    /// UIKit answers by presenting none of them and tearing the editor down instead.
    @State private var swapping: SwapTarget?

    private struct SwapTarget: Identifiable { let id: TrainingExerciseDraft.ID }

    init(template: WorkoutTemplate? = nil, onSave: ((WorkoutTemplate) -> Void)? = nil) {
        self.template = template
        self.onSave = onSave
        _name = State(initialValue: template?.name ?? "")
        _exercises = State(initialValue: template?.orderedExercises.map(TrainingExerciseDraft.init) ?? [])
    }

    private var metric: Bool { profiles.first?.unitsAreMetric ?? model.onboarding.unitsAreMetric }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var activeSplit: String {
        let stored = profiles.first?.activeSplit ?? ""
        let available = Splits.names(in: templates)
        return available.contains(stored) ? stored : (available.first ?? "")
    }
    private var nameIsTaken: Bool {
        let split = template?.splitName ?? activeSplit
        return templates.contains { $0.persistentModelID != template?.persistentModelID &&
            $0.splitName == split &&
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
                        ExerciseEditorRow(exercise: $exercise, metric: metric) {
                            swapping = SwapTarget(id: exercise.id)
                        }
                    }
                    .onDelete { exercises.remove(atOffsets: $0) }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        exercises.append(TrainingExerciseDraft())
                    } label: { Label("Add exercise", systemImage: "plus") }
                } header: { Text("Exercises") } footer: {
                    Text(exercises.isEmpty ? "Add the exercises you want in this session." : "Tap an exercise to swap it for something similar or take it out.")
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
                .sheet(item: $swapping) { target in
                    if let draft = exercises.first(where: { $0.id == target.id }) {
                        ExerciseSwapSheet(current: draft) { pick in
                            guard let index = exercises.firstIndex(where: { $0.id == target.id }) else { return }
                            exercises[index].name = pick.name
                            exercises[index].muscle = pick.muscle
                            exercises[index].increment = pick.increment
                            // The old working weight belongs to the old movement. Carrying
                            // it over would start somebody's first machine press at the
                            // weight they bench.
                            exercises[index].workingWeight = 0
                        } onName: { typed in
                            guard let index = exercises.firstIndex(where: { $0.id == target.id }) else { return }
                            exercises[index].name = typed
                            exercises[index].workingWeight = 0
                        } onRemove: {
                            exercises.removeAll { $0.id == target.id }
                        }
                    }
                }
        }
    }

    private func save() {
        guard canSave else { return }
        // A new session joins the split being looked at. Anywhere else and it would be
        // saved into a list the person who made it cannot see.
        let saved = template ?? WorkoutTemplate(name: cleanName,
                                                order: (templates.map(\.order).max() ?? -1) + 1,
                                                splitName: activeSplit)
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
    var onSwap: () -> Void = {}
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            // Swapping, not typing. A name field is fine if you already know what you
            // want and can spell it, and useless otherwise, which is why a preset
            // somebody disliked stayed disliked instead of getting fixed.
            Button {
                Haptics.light()
                onSwap()
            } label: {
                LabeledContent("Exercise") {
                    HStack(spacing: 6) {
                        Text(exercise.name.isEmpty ? "Choose" : exercise.name)
                            .foregroundStyle(Tokens.textPrimary)
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.caption).foregroundStyle(Tokens.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Swap this exercise for a similar one, or remove it")
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

/// Changing one exercise for another like it.
///
/// The editor used to ask people to type a name. That is fine if you already know what
/// you want and can spell it, and useless otherwise, which is the reason a preset
/// somebody dislikes stays disliked rather than getting fixed. Every exercise belongs to
/// a movement pattern, so the question "what else presses horizontally, with what I have,
/// that does not load what hurts" already has an answer.
///
/// Two ways out and no third: swap it for something in the same pattern, or remove it.
/// A free text box would put the app back where it started.
struct ExerciseSwapSheet: View {
    let current: TrainingExerciseDraft
    let onPick: (CatalogExercise) -> Void
    /// A name the catalogue does not have. Every gym has a machine nobody else does.
    var onName: (String) -> Void = { _ in }
    let onRemove: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var typing: Bool

    private var known: CatalogExercise? { ExerciseCatalog.named(current.name) }

    /// Everything on offer: the alternatives to a known movement, or the whole catalogue
    /// when there is nothing to be an alternative to.
    ///
    /// A session built from scratch starts with a row that has no name, so there was
    /// nothing to compare it with and the sheet said so and offered only Remove. Since
    /// this sheet had replaced the name field, that left no way to say what the exercise
    /// was: creating a session by hand was dead from the moment it opened.
    private var options: [CatalogExercise] {
        let all: [CatalogExercise]
        if let known {
            all = ExerciseCatalog.alternatives(
                to: known,
                equipment: model.onboarding.equipment ?? .fullGym,
                limitations: model.trainingLimitations,
                experience: model.onboarding.experience ?? .regular,
                hasBar: model.onboarding.hasPullUpBar ?? true)
        } else {
            all = ExerciseCatalog.available(
                equipment: model.onboarding.equipment ?? .fullGym,
                limitations: model.trainingLimitations,
                experience: model.onboarding.experience ?? .regular,
                hasBar: model.onboarding.hasPullUpBar ?? true)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private var typedName: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The catalogue does not know every machine in every gym. Anything typed that does
    /// not match becomes the name, rather than being refused.
    private var canUseTypedName: Bool {
        !typedName.isEmpty && !options.contains { $0.name.localizedCaseInsensitiveCompare(typedName) == .orderedSame }
    }

    /// The exercise they typed, when the catalogue knows it and is deliberately not
    /// offering it.
    ///
    /// Typing was added so a session could be built by hand, and it walked straight past
    /// the filter that the whole list exists to apply: a tester with a declared shoulder
    /// injury typed "Overhead press" into their leg day and the app saved it without a
    /// word. Free text cannot be policed in general, and the app has no business
    /// refusing somebody their own training. It does have a duty to say what it knows.
    private var typedButRuledOut: CatalogExercise? {
        guard let match = ExerciseCatalog.named(typedName) else { return nil }
        let allowed = ExerciseCatalog.available(
            equipment: model.onboarding.equipment ?? .fullGym,
            limitations: model.trainingLimitations,
            experience: model.onboarding.experience ?? .regular,
            hasBar: model.onboarding.hasPullUpBar ?? true)
        return allowed.contains(where: { $0.id == match.id }) ? nil : match
    }

    /// Why this one is not in the list, in the words of the answer they gave.
    private func warning(for exercise: CatalogExercise) -> String {
        let hit = (model.trainingLimitations ?? []).filter { exercise.loads.contains($0) }
        if !hit.isEmpty {
            let named = hit.map(\.title.localizedLowercase).sorted().joined(separator: " and ")
            return "You told Jett about your \(named). This one loads that."
        }
        if exercise.needsExperience, model.onboarding.experience == .new {
            return "This is one to learn with somebody watching before you load it."
        }
        return "This needs equipment you said you do not have."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        TextField(known == nil ? "Search, or type any exercise" : "Search", text: $query)
                            .font(.system(size: 16))
                            .focused($typing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.sentences)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        if let ruledOut = typedButRuledOut {
                            // Named, explained, and still theirs to choose. Saying
                            // nothing was the bug; refusing would be the other one.
                            VStack(alignment: .leading, spacing: 10) {
                                Label(warning(for: ruledOut), systemImage: "exclamationmark.triangle")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Tokens.alert)
                                Button {
                                    Haptics.decided()
                                    onPick(ruledOut)
                                    dismiss()
                                } label: {
                                    Text("Add it anyway")
                                        .font(.body.weight(.medium))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Tokens.textPrimary)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else if canUseTypedName {
                            Button {
                                Haptics.decided()
                                onName(typedName)
                                dismiss()
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "plus")
                                    Text("Use \u{201C}\(typedName)\u{201D}")
                                        .font(.body.weight(.medium))
                                    Spacer(minLength: 8)
                                }
                                .frame(minHeight: 44).padding(14).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Tokens.accent)
                            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        if options.isEmpty && typedButRuledOut == nil {
                            EmptyStateView(message: emptyMessage)
                        } else if !options.isEmpty {
                            ListCard {
                                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                                    if index > 0 {
                                        Divider().overlay(Tokens.hairline).padding(.leading, 14)
                                    }
                                    Button {
                                        Haptics.decided()
                                        onPick(option)
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 12) {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(option.name)
                                                    .font(.body.weight(.medium))
                                                    .foregroundStyle(Tokens.textPrimary)
                                                Text(option.equipment.label)
                                                    .font(.caption)
                                                    .foregroundStyle(Tokens.textSecondary)
                                            }
                                            Spacer(minLength: 8)
                                        }
                                        .frame(minHeight: 44).padding(14).contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        Button(role: .destructive) {
                            Haptics.light()
                            onRemove()
                            dismiss()
                        } label: {
                            Label("Remove from this session", systemImage: "minus.circle")
                                .font(.body.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 50)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Tokens.alert)
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(current.name.isEmpty ? "Exercise" : current.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.tint(Tokens.textPrimary)
                }
            }
        }
    }

    /// Three different silences, and they are not the same news.
    private var emptyMessage: String {
        if !typedName.isEmpty { return "Nothing in the list matches that. You can still use the name you typed." }
        return known == nil
            ? "Nothing here fits the equipment and limits you gave. You can type a name instead."
            : "Nothing else trains this the way you have it set up. You can remove it instead."
    }
}

extension ExerciseEquipment {
    var label: String {
        switch self {
        case .barbell: return "Barbell"
        case .machine: return "Machine or cable"
        case .dumbbells: return "Dumbbells"
        case .bodyweight: return "Bodyweight"
        }
    }
}

/// Which split somebody is running right now.
///
/// Installing a starter used to append its sessions to whatever was already there, so
/// trying push/pull/legs for a week left you with eight sessions in one flat list and no
/// way back to the four you had written yourself. A split is a name stamped on its
/// sessions; the Train tab shows one split at a time and switching is a menu.
enum Splits {
    /// What the sessions somebody built themselves are called. They carry no split name,
    /// because they predate splits and because "my own" is not a split anybody chose.
    static let ownName = "My sessions"

    static func display(_ raw: String) -> String { raw.isEmpty ? ownName : raw }

    /// Every split that has a session in it, in the order their sessions were made.
    static func names(in templates: [WorkoutTemplate]) -> [String] {
        var seen: [String] = []
        for template in templates where !seen.contains(template.splitName) {
            seen.append(template.splitName)
        }
        return seen
    }
}
