import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(GymPresence.self) private var gym
    @Environment(\.modelContext) private var context

    /// Armed once per appearance. Without it, marking the moment given would recompute
    /// the beats mid-flight and take him off the screen halfway through his own sentence.
    @State private var jettMomentArmed = true
    @State private var showingWhy = false
    @State private var showingCheckIn = false
    @State private var pickingProgram = false
    @State private var showingAdjust = false
    @State private var activeSession: WorkoutSession?
    @State private var loggingWeight = false
    @State private var openingWeight = false
    @Query(sort: \WeightLog.date) private var weightLogs: [WeightLog]
    @State private var loggingMeal = false
    @State private var editingTemplate: WorkoutTemplate?
    @State private var savedMessage: String?
    @State private var showSaved = false

    static let summaryAnchor = "summary"

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            content
        }
        // Jett's morning. Read from the page rather than positioned by hand, so a card
        // that moves, or is not there today, needs nothing changed here.
        .toolbar(.hidden, for: .navigationBar)
        // Before the header inset, because that is the space the anchors resolve in.
        // Attaching it after moved every frame down by the header's height. The scrim
        // covers the header anyway: it is drawn as one path that extends past its own
        // bounds rather than as a rectangle that stops at them.
        .overlayPreferenceValue(TourAnchors.self) { anchors in
            GeometryReader { proxy in
                if let beats = jettBeats, !beats.isEmpty {
                    JettFlight(beats: beats,
                               frames: anchors.mapValues { proxy[$0] },
                               onFinish: finishJettMoment)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .sheet(isPresented: $showingCheckIn) { CheckInView() }
        .sheet(isPresented: $pickingProgram) {
            NavigationStack { ProgramSetupView { model.selectToday($0); pickingProgram = false } }
        }
        .sheet(item: $activeSession) { LiveWorkoutView(session: $0) }
        .navigationDestination(isPresented: $openingWeight) { WeightDetailView() }
        .sheet(isPresented: $loggingWeight, onDismiss: showSaveResult) { WeightLogView { saved($0) } }
        .sheet(isPresented: $loggingMeal, onDismiss: showSaveResult) { MealLogView { saved($0) } }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorView(template: template) { model.selectToday($0); editingTemplate = nil }
        }
        .alert("Saved", isPresented: $showSaved) { Button("OK", role: .cancel) { savedMessage = nil } } message: { Text(savedMessage ?? "") }
        .sheet(isPresented: $showingAdjust) { AdjustSessionView() }
        .sheet(isPresented: $showingWhy) {
            if let day = model.day, let rec = model.recommendation {
                WhyView(day: day, recommendation: rec)
            }
        }
    }

    /// Every weigh-in with its date, from Health and from what was logged here, one a
    /// day. The card needs dates to say what changed; the series it already had is a
    /// bare list of numbers.
    private var weighIns: [WeightTrend.Reading] {
        let fromHealth = model.series.compactMap { day in
            day.bodyMassKg.map { WeightTrend.Reading(date: day.date, kilograms: $0) }
        }
        let fromLogs = weightLogs.map { WeightTrend.Reading(date: $0.date, kilograms: $0.kilograms) }
        return WeightTrend.daily(fromHealth + fromLogs)
    }

    /// The last six days that have anything recorded on them. Today is the screen you
    /// are already on, so it is not in the list.
    private var recentDays: [Date] {
        let calendar = Calendar.current
        return model.series
            .map { calendar.startOfDay(for: $0.date) }
            .filter { !calendar.isDateInToday($0) && $0 < Date() }
            .suffix(6)
            .reversed()
    }

    private var header: some View {
        HStack {
            // The date is a way back into the week, not a label. A shortcut for the
            // last few days, with the calendar behind it for anything older.
            Menu {
                ForEach(recentDays, id: \.self) { day in
                    Button {
                        Haptics.light()
                        withAnimation(.snappy(duration: 0.3)) { model.viewingDate = day }
                    } label: {
                        Label(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                              systemImage: Calendar.current.isDateInYesterday(day)
                                  ? "clock.arrow.circlepath" : "calendar")
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    if model.isRewound {
                        Text(model.viewedDay,
                             format: .dateTime.weekday(.wide).month(.wide).day())
                    } else {
                        Text("Today, ") + Text(Date(), format: .dateTime.month(.wide).day())
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Tokens.textSecondary)
                }
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.textPrimary)
            }
            Spacer()
            // The only thing that ever sits here, and only while the screen is showing
            // a day that has already happened. Text and a symbol rather than a filled
            // pill: it has to be findable without becoming the loudest thing up here.
            if model.isRewound {
                Button {
                    Haptics.light()
                    withAnimation(.snappy(duration: 0.3)) { model.viewingDate = nil }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Today")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tokens.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .offset(x: 8)))
                .accessibilityLabel("Back to today")
            }
        }
        .padding(.horizontal, Tokens.screenMargin)
        .padding(.top, 6)
        .padding(.bottom, 11)
        .background(Tokens.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Tokens.hairline).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().controlSize(.large).tint(Tokens.accent)
        case .needsOnboarding:
            // RootView shows onboarding over the whole app; this is only ever a frame
            // in between.
            Color.clear
        case .failed:
            dashboard
        case .ready:
            dashboard
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Above everything, because it is a question and it is rare. It
                // disappears the moment it is answered and never comes back for that
                // place.
                if let place = gym.placeToConfirm, !model.isRewound {
                    GymConfirmCard(visit: place,
                                   onConfirm: { gym.confirmGym(named: $0, at: place) },
                                   onDecline: { gym.declineGym(at: place) })
                }
                summaryCard
                if !model.isRewound { checkInPrompt }
                if let error = model.healthReadError { Text("Health couldn't refresh. \(error)").font(.footnote).foregroundStyle(.secondary) }
                // The screen below the fold is composed from the goal, not fixed:
                // someone here to sleep better does not open on a back squat.
                ForEach(blocks, id: \.self) { block in
                    view(for: block)
                }
                if !model.isRewound { insight }
                // A day with nothing on it renders as a void, which reads as the screen
                // having failed rather than as the day having been quiet. A line of grey
                // text in the middle of nothing does not fix that; somebody standing in
                // the empty room does.
                if model.isRewound, blocks.isEmpty || !model.hasAnything(
                    on: model.viewedDay, context: context) {
                    EmptyStateView(message: "Nothing was recorded on this day.")
                }
            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.top, 2)
            .clearsTabBar()
        }
        .accessibilityIdentifier("today-overview")
        .refreshable { await model.refresh() }
    }

    /// The cards for the day on screen.
    ///
    /// The composition is built around what somebody is working on next, which is not
    /// a question a day that has gone can answer. Looking back, the session and the
    /// meals are what happened, so both show whatever the goal was: somebody training
    /// to get stronger still ate on Tuesday.
    ///
    /// Nutrition only when there is some. An empty log, on a day with no way to add to
    /// it, is a card about nothing.
    private var blocks: [HomeBlock] {
        guard model.isRewound else { return model.homeBlocks }
        var blocks = model.homeBlocks
        if !blocks.contains(.session) { blocks.insert(.session, at: 0) }
        if !blocks.contains(.nutrition), loggedNutrition { blocks.append(.nutrition) }
        return blocks
    }

    private var loggedNutrition: Bool {
        let calendar = Calendar.current
        guard let shown = model.series.last(where: {
            calendar.isDate($0.date, inSameDayAs: model.viewedDay)
        }) else { return false }
        return shown.dietaryEnergyKcal != nil || shown.proteinGrams != nil
            || shown.carbohydrateGrams != nil || shown.fatGrams != nil
    }

    /// The day's call, once a morning, and the three rings once ever.
    ///
    /// The walkthrough came out for a version, because reading it Hao could not tell
    /// whether he was looking at onboarding or at Today. Putting it back, because the
    /// version without it is worse: somebody arrives from onboarding, sees three
    /// numbers they have never met, and the app never says what any of them are. The
    /// ambiguity was worth fixing, the explanation was not worth losing.
    ///
    /// Never on a day with no numbers on it. A greeting about a dash is worse than
    /// silence, and the morning after onboarding is exactly when the rings are empty.
    private var jettBeats: [JettBeat]? {
        guard jettMomentArmed, !model.isRewound else { return nil }
        if case .ready = model.phase {} else { return nil }
        let viewed = model.viewedScores(context: context)
        guard viewed.recovery.value != nil, viewed.sleep.value != nil else { return nil }
        guard let rec = model.recommendation, let day = model.day else { return nil }
        // What the numbers say, then what to do about it. He is standing over the rings
        // that carry those numbers, so naming them is the whole sentence.
        let call = MorningGreeting.sentence(
            recovery: viewed.recovery, sleep: viewed.sleep,
            instruction: Copy.call(for: rec, gate: day.readiness.gateApplied,
                                   hasSession: model.hasProgram))

        if !JettMoments.hasWalkedThrough {
            // Say hello before explaining anything. He used to arrive on somebody's
            // first morning already mid-sentence about what recovery means, which is a
            // manual opening itself rather than being greeted by a coach.
            return [JettBeat(anchor: nil, text: "Hey, welcome in. Let me show you around.")]
                + Signal.allCases.map { JettBeat(anchor: $0.rawValue, text: $0.meaning) }
                + [JettBeat(anchor: TodayView.summaryAnchor, text: call)]
        }
        guard !JettMoments.hasGreeted(on: Date()) else { return nil }
        return [JettBeat(anchor: TodayView.summaryAnchor, text: call)]
    }

    private func finishJettMoment() {
        JettMoments.markWalkedThrough()
        JettMoments.markGreeted(on: Date())
        jettMomentArmed = false
    }

    private func saved(_ message: String) { savedMessage = message }
    private func showSaveResult() { if savedMessage != nil { showSaved = true } }

    // MARK: - Rings and coaching, one card

    /// The rings on their own.
    ///
    /// The coaching card used to sit under them carrying the day's call. Jett flies up
    /// and says that line himself now, so the card was the same sentence twice: once
    /// from him and once from a box. Taken out rather than reworded, because a second
    /// voice saying the same thing is not a layout problem.
    private var summaryCard: some View {
        let viewed = model.viewedScores(context: context)
        return HStack(spacing: 0) {
            ringCell(.strain, percent: Self.percent(viewed.strain),
                     recovery: viewed.recovery.value)
                .explains(Signal.strain.rawValue)
            cellDivider
            ringCell(.recovery, percent: Self.percent(viewed.recovery),
                     recovery: viewed.recovery.value)
                .explains(Signal.recovery.rawValue)
            cellDivider
            ringCell(.sleep, percent: Self.percent(viewed.sleep),
                     recovery: viewed.recovery.value)
                .explains(Signal.sleep.rawValue)
        }
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity)
        .background(Tokens.surface,
                    in: RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 4)
        // Published from a background rather than from the card itself. An anchor set
        // on a container replaces whatever its children published, so `.explains` here
        // silently wiped the three ring anchors and every beat lost its target: no
        // spotlight, and Jett parked in the middle of the screen.
        .background { Color.clear.explains(TodayView.summaryAnchor) }
    }

    /// Never zero. A ring drawn at nothing reads as broken rather than as low, which
    /// is the same reason the live accessors clamp at one.
    private static func percent(_ score: SignalScore) -> Int? {
        score.value.map { max(1, Int($0.rounded())) }
    }

    private var cellDivider: some View {
        Rectangle().fill(Tokens.hairline).frame(width: 1).padding(.vertical, 2)
    }

    /// `recovery` is the day on screen's, not today's: the strain ring draws its target
    /// arc from recovery, and a rewound Tuesday was drawing Saturday's.
    ///
    /// The ring opens its own screen; the mark beside the title opens how the day's
    /// call was made. That used to hang off the coaching card, which is gone, and it
    /// is the one explanation in the app that is about the morning rather than about
    /// one number.
    private func ringCell(_ signal: Signal, percent: Int?, recovery: Double?) -> some View {
        VStack(spacing: 9) {
            NavigationLink {
                // The day that was tapped, so the screen behind a ring says what the
                // ring said. Without it every ring on a past day opened on today.
                SignalDetailView(signal: signal, date: model.viewedDay)
            } label: {
                RingGauge(signal: signal, percent: percent,
                          target: signal == .strain
                              ? StrainScore.target(recovery: recovery) : nil,
                          lineWidth: 9, figureSize: 23)
                    .frame(width: 78, height: 78)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // The mark hangs off the title rather than sitting beside it in a row.
            // In a row the pair is centred as one thing, so every label shifted left by
            // half an icon and stopped lining up with the ring above it.
            Text(signal.title)
                .font(.system(size: 13))
                .foregroundStyle(Tokens.textSecondary)
                .frame(height: 20)
                .overlay(alignment: .trailing) {
                    if model.recommendation != nil, model.day != nil, !model.isRewound {
                        Button { Haptics.light(); showingWhy = true } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.textTertiary)
                                .frame(width: 30, height: 30)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .offset(x: 24)
                        .accessibilityLabel("How today's call was made")
                    }
                }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Session

    @ViewBuilder
    private var session: some View {
        let templates = (try? context.fetch(
            FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\WorkoutTemplate.order)]))) ?? []
        if let planned = model.plannedToday(templates: templates) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Today's session").sectionHeading()
                PlannedSessionCard(template: planned, recommendation: model.recommendation,
                    onChange: { pickingProgram = true }, onEdit: { editingTemplate = planned },
                    onStart: { activeSession = WorkoutSession.today(in: context, named: planned.name) })
            }
        }
    }

    // MARK: - Check-in

    /// Asks once, then gets out of the way. A saved check-in is something the user
    /// already knows; it does not need a row saying so.
    @ViewBuilder
    private var checkInPrompt: some View {
        if model.todayCheckIn == nil {
            Button { Haptics.light(); showingCheckIn = true } label: {
                HStack(spacing: 11) {
                    // The one coloured icon left outside a ring, and it earns it: this
                    // is a single call to action rather than a row in a grid of
                    // readings, and a sunrise the colour of one says "morning" before
                    // the words are read.
                    Image(systemName: "sun.horizon.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Tokens.strainLow)
                    Text("How are you feeling?")
                        .font(.body.weight(.semibold)).foregroundStyle(Tokens.textPrimary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 16).frame(minHeight: 58)
                // Outlined, not filled, and no arrow. A tinted slab and an arrow were
                // two ways of saying the same thing, and the slab made the smallest
                // question on the screen its loudest object. A border reads as a
                // control on its own; the press does the rest.
                .background {
                    RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
                        .strokeBorder(Tokens.textPrimary.opacity(0.14), lineWidth: 1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: - Insight

    /// One pattern, or nothing at all.
    @ViewBuilder
    private var insight: some View {
        if let line = model.recentInsight {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pattern").sectionHeading()
                Text(line)
                    .font(.system(size: 15))
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .bevelCard()
            }
        }
    }

    // MARK: - Goal-driven blocks

    @ViewBuilder
    private func view(for block: HomeBlock) -> some View {
        // The row for whichever day is on screen. Every card below reads this, so
        // rewinding moves all of them together rather than one at a time.
        let calendar = Calendar.current
        let shown = model.series.last { calendar.isDate($0.date, inSameDayAs: model.viewedDay) }
        let past = model.isRewound
        switch block {
        case .session:
            // A plan is a thing you are about to do. On a day already gone the only
            // honest version is what was actually lifted, which the history holds.
            if past { loggedThatDay } else { session }
        case .programPrompt:
            if !past { programPrompt }
        case .nutrition:
            NutritionCard(calories: shown?.dietaryEnergyKcal, protein: shown?.proteinGrams,
                carbs: shown?.carbohydrateGrams, fat: shown?.fatGrams,
                onLog: past ? nil : { loggingMeal = true })
        case .weightTrend:
            let weight = model.weight(asOf: model.viewedDay)
            WeightTrendCard(latest: weight.latest, series: weight.series,
                metric: model.onboarding.unitsAreMetric,
                dated: weighIns,
                onLog: past ? nil : { loggingWeight = true },
                onOpen: { openingWeight = true })
        case .sleepQuality:
            SleepQualityCard(night: shown?.sleep,
                             summary: model.viewedScores(context: context).sleep.summary)
        case .sleepDebt:
            SleepDebtCard(debt: model.sleepDebt(on: model.viewedDay))
        case .movement:
            MovementCard(activeEnergy: shown?.activeEnergyKcal, steps: shown?.steps,
                         exerciseMinutes: shown?.exerciseMinutes)
        }
    }

    /// What was lifted on the day being read, rather than a session to start.
    @ViewBuilder
    /// All of them, not the first. Two sessions in a day is a normal thing to do, and
    /// showing one of them on the screen whose whole job is what happened is a quiet
    /// lie about the day.
    private var loggedThatDay: some View {
        let all = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let thatDay = all.filter {
            Calendar.current.isDate($0.date, inSameDayAs: model.viewedDay) && !$0.sets.isEmpty
        }.sorted { $0.date < $1.date }
        return ForEach(thatDay) { session in
            VStack(alignment: .leading, spacing: 12) {
                Text(session.templateName).sectionHeading()
                ListCard {
                    ForEach(Array(session.orderedSets.enumerated()), id: \.element.id) { index, set in
                        if index > 0 {
                            Divider().overlay(Tokens.hairline).padding(.leading, 14)
                        }
                        FieldRow(label: set.exerciseName) {
                            Text("\(Int(set.load.rounded())) lb × \(set.reps)").monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    private var programPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training").sectionHeading()
            AccessoryRow(symbol: "square.stack.3d.up", label: "Build your training plan") {
                pickingProgram = true
            }
        }
    }

}
