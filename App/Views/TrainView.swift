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

    /// The split being shown. A name that no longer has any sessions in it falls back to
    /// the first split that does, so deleting the last session of a split cannot leave
    /// the tab looking empty while sessions exist.
    private var activeSplit: String {
        let stored = profiles.first?.activeSplit ?? ""
        let available = Splits.names(in: templates)
        return available.contains(stored) ? stored : (available.first ?? "")
    }
    private var splitTemplates: [WorkoutTemplate] {
        templates.filter { $0.splitName == activeSplit }
    }
    private func show(_ split: String) {
        profiles.first?.activeSplit = split
        expandedTemplates.removeAll()
        Haptics.selected()
    }

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) { content }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.top, 4).clearsTabBar()
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
        // Arriving from the Lock Screen's End. Opening the session is the whole job:
        // Finish is already in there, and it is the screen that knows what was logged.
        .onChange(of: model.wantsToFinishWorkout) { _, wants in
            guard wants else { return }
            model.wantsToFinishWorkout = false
            liveSession = sessions.first { !$0.isComplete }
        }
        .sheet(item: $editingTemplate) { TemplateEditorView(template: $0) }
        .sheet(isPresented: $creatingSession) {
            TemplateEditorView(onSave: { model.selectToday($0) })
        }
        .sheet(isPresented: $choosingSplit) { NavigationStack { ProgramSetupView() } }
    }

    /// Nothing at all, or the two sections.
    ///
    /// A first open has no split and no history, which is two empty sections and one
    /// blank page. The sections each said so in their own grey sentence, which reads as
    /// two things having failed rather than as a tab waiting to be used.
    @ViewBuilder
    private var content: some View {
        if templates.isEmpty && sessions.isEmpty {
            EmptyStateView(message: "No split yet. Start from one Jett picked, "
                                  + "or build a session yourself.") {
                ListCard {
                    AccessoryRow(symbol: "dumbbell", label: "Choose a starter split") {
                        choosingSplit = true
                    }
                    Divider().overlay(Tokens.hairline)
                    AccessoryRow(symbol: "plus", label: "Create a session") {
                        creatingSession = true
                    }
                }
            }
        } else {
            program
            history
        }
    }

    /// The heading names the split, and is the way to change it. One heading that also
    /// switches rather than a heading plus a picker: there is only ever one answer on
    /// screen, so the thing showing it is the thing to press.
    @ViewBuilder
    private var splitHeading: some View {
        let names = Splits.names(in: templates)
        if names.count > 1 {
            Menu {
                Picker("Split", selection: Binding(get: { activeSplit }, set: { show($0) })) {
                    ForEach(names, id: \.self) { Text(Splits.display($0)).tag($0) }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(Splits.display(activeSplit)).sectionHeading()
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        .foregroundStyle(Tokens.textSecondary)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Split: \(Splits.display(activeSplit)). Change split.")
        } else {
            Text("Your split").sectionHeading()
        }
    }

    private var program: some View {
        VStack(alignment: .leading, spacing: 12) {
            splitHeading
            if splitTemplates.isEmpty {
                ListCard {
                    AccessoryRow(symbol: "dumbbell", label: "Choose a starter split") { choosingSplit = true }
                    Divider().overlay(Tokens.hairline)
                    AccessoryRow(symbol: "plus", label: "Create a session") { creatingSession = true }
                }
            }
            ForEach(splitTemplates) { template in
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
    /// Newest first, for starting a set where the last one of these finished.
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var profiles: [UserProfile]
    @State private var exerciseIndex = 0
    @State private var restRemaining = 0
    @State private var restTimer: Timer?
    @State private var showingFinish = false
    /// Pounds, always, whatever the wheel is showing.
    @State private var weight = 0.0
    @State private var reps = 8
    @State private var rir = 2
    @State private var saveError = false
    @State private var dictation = Dictation()
    /// What speaking produced, held until the user commits it. Nothing is written to
    /// the day off a transcript alone: a misheard set is worse than a typed one.
    @State private var heard: SpokenSetResolver.Resolution?
    @State private var heardNothing: String?

    private var metric: Bool { profiles.first?.unitsAreMetric ?? model.onboarding.unitsAreMetric }
    private var unit: String { metric ? "kg" : "lb" }
    private var template: WorkoutTemplate? { templates.first { $0.name == session.templateName } }
    private var exercises: [TemplateExercise] { template?.orderedExercises ?? [] }
    private var current: TemplateExercise? { exercises.indices.contains(exerciseIndex) ? exercises[exerciseIndex] : nil }
    private var setsLogged: Int {
        guard let current else { return 0 }
        return session.sets.filter { $0.exerciseName == current.name && !$0.isWarmup }.count
    }
    /// The ceiling is kept even though a wheel cannot overshoot it, because the spoken
    /// path writes here too and a misheard number is the same bad set.
    private var enteredLoad: Double? {
        guard weight.isFinite, weight >= 0,
              weight <= SpokenSetParser.maximumReasonableLoad else { return nil }
        return weight
    }

    /// Every plate you could put on this, in the smallest step it actually moves in.
    ///
    /// The step is the exercise's own: a dumbbell curl goes up in 2.5 and a leg press in
    /// 10, and a wheel that offers a 2.5 lb change on a leg press is a wheel nobody can
    /// reach the end of. Zero stays on the list, because bodyweight sets are sets.
    private func loadOptions(for exercise: TemplateExercise) -> [Double] {
        let step = exercise.increment > 0 ? exercise.increment : 2.5
        let top = SpokenSetParser.maximumReasonableLoad
        var options = stride(from: 0.0, through: top, by: step).map { $0 }
        // Whatever they last used belongs on the wheel even when it is off the grid,
        // which happens on a machine with its own plate numbers.
        if !options.contains(weight), weight > 0, weight <= top {
            options.append(weight)
            options.sort()
        }
        return options
    }

    private func wheel<Content: View>(label: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Text(label).microLabel()
            content()
        }
        .frame(maxWidth: .infinity)
    }

    /// What reps in reserve is, without saying reps in reserve.
    ///
    /// The engine wants a number and the person does not have one. Nobody outside a
    /// coaching qualification knows what RIR means, and a stepper from 0 to 6 asks them
    /// to guess at a scale nobody explained. Three answers everybody can give, mapped
    /// back to the number the engine has always used.
    private var effortPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How hard was that?").microLabel()
            HStack(spacing: 8) {
                // Four in reserve, not three. Three is inside the engine's own line for a
                // hard set, so a session where somebody answered Comfortable to every
                // question came back saying "Hard sets: 12". The word and the arithmetic
                // have to agree, and with only three answers on offer there was no way
                // to log a set that was genuinely easy.
                effortOption("Comfortable", rir: StrainEngine.hardSetRIRThreshold + 1)
                effortOption("Hard", rir: 1)
                effortOption("All out", rir: 0)
            }
        }
    }

    /// Which of the three a stored reps-in-reserve belongs to.
    ///
    /// The plan's own target is 2 or 3 depending on experience, and matching on equality
    /// meant arriving at this screen with nothing selected at all, which reads as a
    /// question that has not been answered rather than one with a sensible default.
    private func effortBucket(_ value: Int) -> Int {
        switch value {
        case 0: return 0
        case 1: return 1
        default: return StrainEngine.hardSetRIRThreshold + 1
        }
    }

    private func effortOption(_ label: String, rir value: Int) -> some View {
        let selected = effortBucket(rir) == value
        return Button {
            Haptics.selected()
            rir = value
        } label: {
            Text(label)
                .font(.system(size: 15, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Tokens.messageOnOutgoing : Tokens.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selected ? Tokens.messageOutgoing : Tokens.surface,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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
                ToolbarItem(placement: .cancellationAction) {
                    // Closing the sheet leaves the session open, so the activity stays:
                    // that is the whole point of it being on the Lock Screen.
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Finish") { showingFinish = true }.fontWeight(.semibold)
                        .disabled(session.sets.isEmpty)
                }
            }
            .tint(Tokens.accent)
            .onAppear {
                prepareSet()
                // The phone spends most of a workout face down on a bench, so the Lock
                // Screen is the only surface the app has during the part it is for.
                if let current {
                    WorkoutActivity.start(template: session.templateName,
                                          exercise: current.name,
                                          setsPlanned: current.targetSets)
                }
            }
            .onChange(of: exerciseIndex) { _, _ in prepareSet() }
            .onDisappear { stopTimer(); dictation.stop() }
            .onChange(of: exerciseIndex) { _, _ in showActivity() }
            .sheet(isPresented: $showingFinish) {
                FinishSessionView(session: session) {
                    stopTimer()
                    WorkoutActivity.end()
                    dismiss()
                }
            }
            .alert("Set wasn’t saved", isPresented: $saveError) {
                Button("OK", role: .cancel) {}
            } message: { Text("Please try logging the set again.") }
        }
    }

    private func working(_ exercise: TemplateExercise) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 6) {
                step(-1, symbol: "chevron.left", label: "Previous exercise",
                     enabled: exerciseIndex > 0)
                VStack(alignment: .leading, spacing: 5) {
                    Text(exercise.name).font(.title2.weight(.bold))
                        .foregroundStyle(Tokens.textPrimary)
                    Text(setsLogged < exercise.targetSets
                         ? "Set \(setsLogged + 1) of \(exercise.targetSets)"
                         : "Set \(setsLogged + 1)")
                        .font(.subheadline).foregroundStyle(Tokens.textSecondary)
                }
                Spacer(minLength: 4)
                step(1, symbol: "chevron.right", label: "Next exercise",
                     enabled: exerciseIndex < exercises.count - 1)
            }
            // Two wheels and three words, because this is done between sets with one
            // hand and a heart rate of 150. A keyboard for the weight meant tapping a
            // field, waiting for the pad, typing, then dismissing it.
            HStack(spacing: 0) {
                wheel(label: "Weight (\(unit))") {
                    Picker("Weight", selection: $weight) {
                        ForEach(loadOptions(for: exercise), id: \.self) { value in
                            Text(displayLoad(value)).monospacedDigit().tag(value)
                        }
                    }
                    .pickerStyle(.wheel)
                    .accessibilityLabel("Set weight in \(metric ? "kilograms" : "pounds")")
                }
                wheel(label: "Reps") {
                    Picker("Reps", selection: $reps) {
                        ForEach(1...50, id: \.self) { Text("\($0)").monospacedDigit().tag($0) }
                    }
                    .pickerStyle(.wheel)
                }
            }
            .frame(height: 150)

            effortPicker

            if restRemaining > 0 {
                HStack {
                    Label("Rest \(restRemaining)s", systemImage: "timer")
                        .font(.body.monospacedDigit()).foregroundStyle(Tokens.textSecondary)
                    Spacer()
                    Button(action: stopTimer) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Tokens.textPrimary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Skip rest")
                }
                .frame(minHeight: 44)
            }
            dictationStrip(exercise)
            HStack(spacing: 10) {
                PrimaryButton(label: "Log set", tint: Tokens.strainLow,
                              enabled: enteredLoad != nil) { logSet(exercise) }
                microphone(exercise)
            }
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

    /// One colour whatever it does, because moving to the next lift is neither good news
    /// nor bad. Dimmed rather than hidden at the ends, so the row never changes shape.
    private func step(_ delta: Int, symbol: String, label: String,
                      enabled: Bool) -> some View {
        Button {
            guard enabled else { return }
            Haptics.light()
            exerciseIndex += delta
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(enabled ? Tokens.textPrimary : Tokens.textSecondary.opacity(0.35))
                .frame(width: 40, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    /// Tap to talk, tap to stop. Held-down buttons are the wrong shape for this: you
    /// are usually still catching your breath when you start the sentence.
    private func microphone(_ exercise: TemplateExercise) -> some View {
        Button {
            Haptics.decided()
            if dictation.isListening { finishListening(exercise) } else { beginListening() }
        } label: {
            Image(systemName: dictation.isListening ? "stop.fill" : "mic.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(dictation.isListening ? Tokens.onAction : Tokens.textPrimary)
                .frame(width: 54, height: 50)
                .background(dictation.isListening ? Tokens.strainLow : Color.primary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(dictation.isListening ? "Stop listening" : "Say the set instead")
    }

    /// Only ever on screen when there is something in it: the words as they arrive,
    /// then what they were understood to mean.
    @ViewBuilder
    private func dictationStrip(_ exercise: TemplateExercise) -> some View {
        if case let .unavailable(reason) = dictation.status {
            Text(reason).font(.caption).foregroundStyle(Tokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if dictation.isListening {
            ListeningRow(transcript: dictation.transcript)
        } else if let heard {
            SpokenSetCard(resolution: heard, metric: metric,
                          log: { commitHeard(exercise) },
                          discard: { self.heard = nil })
        } else if let heardNothing {
            Text(heardNothing).font(.caption).foregroundStyle(Tokens.textSecondary)
        }
    }

    private func beginListening() {
        heard = nil
        heardNothing = nil
        dictation.reset()
        Task { await dictation.start() }
    }

    private func finishListening(_ exercise: TemplateExercise) {
        let spoken = dictation.stop()
        let programme = exercises.map(\.plannedExercise)
        switch SpokenSetResolver.resolve(spoken, current: exercise.plannedExercise,
                                         programme: programme, unitsAreMetric: metric) {
        case .ready(let resolution):
            heard = resolution
        case .needsReps:
            heardNothing = "I caught that, but not how many reps."
        case .needsExercise, .heardNothing:
            heardNothing = spoken.isEmpty ? "I didn\u{2019}t hear anything."
                                          : "I didn\u{2019}t catch a set in that."
        }
    }

    private func commitHeard(_ exercise: TemplateExercise) {
        guard let resolution = heard else { return }
        let planned = exercises.first {
            $0.name.caseInsensitiveCompare(resolution.exercise.name) == .orderedSame
        }
        SpokenSetWriter.write(resolution, muscleGroup: planned?.muscleGroup ?? exercise.muscleGroup,
                              into: session, in: context)
        Haptics.committed()
        heard = nil
        // The screen follows what was said: logging squats out loud while bench is open
        // should leave squats open, or the next set goes somewhere else.
        if let planned, let index = exercises.firstIndex(where: { $0.id == planned.id }) {
            if index == exerciseIndex { prepareSet() } else { exerciseIndex = index }
        } else {
            prepareSet()
        }
        startRest(seconds: planned?.restSeconds ?? exercise.restSeconds)
    }

    /// Pushed after anything that changes what somebody would want to read at arm's
    /// length: a set landing, a rest starting or being skipped, a change of lift.
    private func showActivity() {
        guard let current else { return }
        WorkoutActivity.update(
            exercise: current.name,
            setsDone: setsLogged,
            setsPlanned: current.targetSets,
            restEnds: restRemaining > 0
                ? Date().addingTimeInterval(TimeInterval(restRemaining)) : nil,
            totalSets: session.sets.count)
    }

    /// Start where they left off.
    ///
    /// This session first, then the last time they did this movement at all. The second
    /// half is the point: the first set of a bench press should not start at zero every
    /// Monday when the app already knows what went on the bar last Monday.
    private func prepareSet() {
        guard let current else { return }
        let last = session.orderedSets.last { $0.exerciseName == current.name }
            ?? lastTime(current.name)
        weight = last?.load ?? (current.workingWeight > 0 ? current.workingWeight : 0)
        reps = last?.reps ?? current.targetReps
        rir = last?.rir ?? current.targetRIR
    }

    private func lastTime(_ exercise: String) -> LoggedSet? {
        sessions.lazy
            .filter { $0 !== session }
            .compactMap { $0.orderedSets.last { $0.exerciseName == exercise } }
            .first
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
        showActivity()
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
        let wasResting = restRemaining > 0
        restTimer?.invalidate()
        restTimer = nil
        restRemaining = 0
        // Only when a rest was actually cut short. Called on the way out of the screen
        // too, where pushing an update to an activity about to end is wasted work.
        if wasResting { showActivity() }
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
