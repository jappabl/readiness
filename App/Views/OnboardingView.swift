import SwiftUI
import SwiftData

/// The first part of the same conversation that continues in CoachSheet.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var flow = OnboardingDraft.restore() ?? OnboardingConversation()
    @State private var visibleCount = 0
    @State private var connecting = false
    @State private var connectionDone = false
    @State private var startedAt = Date()
    @State private var receiptAnswerID: Int?
    @State private var deliveryStatus = ""
    @State private var reactedAnswers: Set<Int> = []
    @Environment(Notifications.self) private var notifications
    /// Pounds, or kilos when that is how they read everything else.
    @State private var weightEntry = 170.0
    @State private var celebrating = false

    private var settled: Bool { visibleCount == flow.turns.count }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10),
              count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            CoachContactHeader(isThinking: flow.step == .reading && !connectionDone)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Today \(startedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Tokens.textTertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 8)
                        ForEach(Array(flow.turns.prefix(visibleCount))) { turn in
                            turnView(turn)
                                .transition(reduceMotion ? .opacity :
                                    .offset(x: turn.isUser ? 12 : 0, y: 10).combined(with: .opacity))
                        }
                        if settled {
                            responses
                                // The choices arrive as their own beat rather than
                                // snapping in the instant the sentence lands.
                                .transition(reduceMotion ? .opacity :
                                    .offset(y: 8).combined(with: .opacity))
                        }
                        if flow.step == .reading { reading }
                        Color.clear.frame(height: 1).id("latest")
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.top, 24)
                    .padding(.bottom, 20)
                }
                .background {
                    GeometryReader { geometry in
                        Color.clear.onChange(of: geometry.size.height) { scroll(proxy) }
                    }
                }
                .conversationScrollAnchor()
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: visibleCount) { scrollAfterLayout(proxy) }
                .onChange(of: flow.step) { scrollAfterLayout(proxy) }
                .onChange(of: typeSize) {
                    Task { @MainActor in
                        await Task.yield()
                        scroll(proxy)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.messageCanvas.ignoresSafeArea())
        // Over everything, hit testing nothing. It is the only thing in this app that
        // celebrates, and it happens once, to a hundred people.
        .overlay { if celebrating { Confetti().ignoresSafeArea() } }
        .onAppear {
            resumeIfSaved()
            Analytics.record(.onboardingStarted)
        }
        // Claimed here rather than lazily on the first message to Jett, because somebody
        // has to be told their number while they are still in the conversation where it
        // means something. Failing is fine and silent: the app asks again on launch, and
        // Profile shows it whenever it turns up.
        .task { await AppAttest.claimMember() }
        .task(id: flow.turns.count) {
            visibleCount = min(visibleCount, flow.turns.count)
            do {
                while visibleCount < flow.turns.count {
                    let answer = flow.turns.prefix(visibleCount).last
                    if let answer, answer.isUser {
                        // Acknowledge the tap first, then give the reply a readable beat.
                        // The whole sequence runs at about half pace: at the old timings
                        // delivered, read, reacted and replied arrived inside a second
                        // and a half, which reads as a machine working through a list
                        // rather than somebody picking up their phone.
                        try await Task.sleep(for: .milliseconds(260))
                        deliveryStatus = "Delivered"
                        // Long enough to read as somebody glancing at their phone,
                        // short enough not to be a wait. The whole delivered-to-read
                        // stretch was a second and a half, which is a pause rather than
                        // a beat.
                        try await Task.sleep(for: .milliseconds(620))
                        deliveryStatus = "Read " + Date().formatted(date: .omitted, time: .shortened)
                        if !reduceMotion { Haptics.wasRead() }
                        // Long enough that reading and reacting are two events. Under
                        // about a third of a second the two taps blur into one.
                        try await Task.sleep(for: .milliseconds(380))
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.34)) {
                            _ = reactedAnswers.insert(answer.id)
                        }
                        if !reduceMotion, answer.reaction != nil { Haptics.reacted() }
                        // Then the pause before the reply, scaled by how much there is
                        // to type, the way a longer answer takes longer to write.
                        let replyLength = flow.turns[visibleCount].text.count
                        let remaining = min(1300, max(560, replyLength * 14))
                        try await Task.sleep(for: .milliseconds(remaining))
                    } else {
                        try await Task.sleep(for: .milliseconds(1150))
                    }
                    guard !Task.isCancelled else { return }
                    Haptics.replyBegan()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
                        visibleCount += 1
                    }
                    Haptics.replyEnded()
                }
                // Settled: the sentence has landed and the choices are now on screen.
                // A separate, lighter tap from the one that marks a turn arriving, so
                // "Jett said something" and "it's your move" do not feel the same.
                if flow.step != .reading && !reduceMotion { Haptics.light() }
            } catch { return }
        }
    }

    @ViewBuilder
    private func turnView(_ turn: OnboardingConversation.Turn) -> some View {
        let message = CoachMessage(role: turn.isUser ? .user : .assistant, text: turn.text,
                                   reaction: reactedAnswers.contains(turn.id) ? turn.reaction : nil)
        let editable = turn.id == flow.latestEditableAnswerID && settled && !connecting
        if turn.isUser {
            // The tap lives on the bubble and on the word Edit, never on the turn as a
            // whole. A button around the turn made the empty gutter beside the answer
            // tappable, and that gutter sits directly above the next question, so a
            // thumb aimed at the top-left choice and landing an inch high rewound the
            // conversation instead. It looked exactly like the app refusing to take an
            // answer, because nothing on screen said what had happened.
            // The word Edit, and nothing else.
            //
            // The bubble was a button too. Removing the gutter beside it stopped the
            // worst of it, but three testers still lost answers to a tap they did not
            // know they had made: one reported being unable to get past the injuries
            // question, one found the chat "silently jumping backward", and one tapped
            // the privacy disclosure under an answer and watched that answer vanish. A
            // control nobody can see is a control nobody meant to press, and the visible
            // one is four characters away.
            answerWithReceipt(message, turnID: turn.id, editable: editable,
                              reservesReactionSpace: turn.reaction != nil,
                              onEdit: editable ? { edit(turn.id) } : nil,
                              tappableBubble: false)
            .accessibilityRemoveTraits(editable ? [] : .isButton)
            .accessibilityAddTraits(editable ? .isButton : [])
            .accessibilityLabel("You: \(turn.text)" + (message.reaction.map { ". Jett reacted with \($0.rawValue)" } ?? ""))
            .accessibilityHint(editable ? "Double tap to change this answer" : "")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                answerWithReceipt(message, turnID: turn.id, editable: false)
                // Talk goes in a bubble; a chart is content and runs full width under
                // it. This is the one turn in onboarding that carries one, and it is
                // the user's own history rather than an illustration of it.
                if turn.chart != nil {
                    // Not CoachChartCard: that one tints by today's reading and writes
                    // its narration from it, and at the end of onboarding there is no
                    // today yet, so it renders grey and silent. This shows the baseline
                    // instead, which is what the sentence above it actually claims.
                    BaselineReveal(series: model.series)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// Done, in a row that is always there.
    ///
    /// It used to appear the moment the first option was chosen, which pushed the whole
    /// grid up between one tap and the next. On a multi-select that is exactly when
    /// somebody is reaching for their second option, and it lands on the space the chip
    /// used to occupy. Every tester who moved quickly through these two questions
    /// reported a chip as dead, and four of them concluded the app was broken. The space
    /// is reserved now, so nothing moves under a thumb.
    private func doneRow(enabled: Bool, action: @escaping () -> Void) -> some View {
        Button("Done", action: action)
            .font(.body.weight(.semibold))
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .tint(Tokens.messageOutgoing)
            .opacity(enabled ? 1 : 0)
            .disabled(!enabled)
            .accessibilityHidden(!enabled)
    }

    /// Told once, to a hundred people, in the conversation where it happened.
    ///
    /// Not a card and not a sheet: it belongs in the chat, because being one of the
    /// first hundred is something Jett tells you, not something the app files under
    /// your account. Everybody else sees nothing here at all. Their number is in
    /// Profile, and a consolation message for not being early is worse than silence.
    @ViewBuilder
    private var foundingWelcome: some View {
        if let member = AppAttest.member, FoundingMember.isFounder(member) {
            HStack(spacing: 12) {
                Text("#\(member)")
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.messageOutgoing)
                Text("You're a founding member!")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.messageIncoming,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            .onAppear {
                Haptics.committed()
                celebrating = true
            }
        }
    }

    private func edit(_ turnID: Int) {
        Haptics.light()
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) {
            flow.editAnswer(id: turnID)
            visibleCount = flow.turns.count
            receiptAnswerID = nil
        }
    }

    private func answerWithReceipt(_ message: CoachMessage, turnID: Int, editable: Bool,
                                   reservesReactionSpace: Bool = false,
                                   onEdit: (() -> Void)? = nil,
                                   tappableBubble: Bool = true) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            CoachTurnView(message: message, reservesReactionSpace: reservesReactionSpace,
                          revealsWords: message.role == .assistant,
                          onTap: tappableBubble ? onEdit : nil)
            if receiptAnswerID == turnID {
                HStack(spacing: 5) {
                    Text(deliveryStatus)
                    if editable, let onEdit {
                        Text("·").accessibilityHidden(true)
                        Button("Edit", action: onEdit)
                            .buttonStyle(.plain)
                            // The only way back, so it gets a thumb-sized target rather
                            // than the eleven points its text occupies. The padding is
                            // taken back out of the layout below, because the first
                            // version of this pushed the whole receipt a centimetre
                            // clear of the bubble it belongs to and read as a gap.
                            .padding(.vertical, 12)
                            .padding(.leading, 8)
                            .contentShape(Rectangle())
                            .accessibilityLabel("Change this answer")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Tokens.textTertiary)
                .contentTransition(.opacity)
                // Takes back the Edit button's tap padding, and only when that button
                // is there. Applied to a receipt with no Edit it pulled "Read" twelve
                // points up into the bubble above, which is what testers saw after
                // the Health step and on the last answer.
                .padding(.vertical, editable && onEdit != nil ? -12 : 0)
            }
        }
    }

    @ViewBuilder private var responses: some View {
        switch flow.step {
        case .goal:
            VStack(spacing: 14) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(TrainingGoal.allCases, id: \.self) { goal in
                        choice(goal.title, symbol: goal.symbol,
                               selected: flow.answers.selectedGoals.contains(goal)) {
                            Haptics.decided()
                            flow.toggleGoal(goal)
                        }
                    }
                }
                Button("Continue") { commit { flow.confirmGoals() } }
                    .font(.body.weight(.semibold))
                    .frame(minHeight: 44).frame(maxWidth: .infinity, alignment: .trailing)
                    .tint(Tokens.messageOutgoing)
                    .disabled(flow.answers.selectedGoals.isEmpty)
            }
        case .frequency:
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(TrainingFrequency.allCases, id: \.self) { frequency in
                    choice(frequency.title, detail: frequency.detail) {
                        commit { flow.chooseFrequency(frequency) }
                    }
                }
            }
        case .experience:
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(TrainingExperience.allCases, id: \.self) { experience in
                    choice(experience.title, detail: experience.detail) {
                        commit { flow.chooseExperience(experience) }
                    }
                }
            }
        case .limitations:
            VStack(spacing: 14) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(PhysicalLimitation.allCases, id: \.self) { limitation in
                        choice(limitation.title, selected: flow.answers.limitations?.contains(limitation) == true) {
                            Haptics.decided()
                            flow.toggleLimitation(limitation)
                        }
                    }
                    choice("None") { commit { flow.confirmLimitations(none: true) } }
                }
                doneRow(enabled: flow.answers.limitations?.isEmpty == false) {
                    commit { flow.confirmLimitations() }
                }
            }
        case .equipment:
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(EquipmentAccess.allCases, id: \.self) { equipment in
                    choice(equipment.title, detail: equipment.detail) {
                        commit { flow.chooseEquipment(equipment) }
                    }
                }
            }
        case .pullUpBar:
            LazyVGrid(columns: columns, spacing: 10) {
                choice("Yes", detail: "Bar or beam") {
                    commit { flow.choosePullUpBar(has: true) }
                }
                choice("No", detail: "Floor only") {
                    commit { flow.choosePullUpBar(has: false) }
                }
            }
        case .watch:
            LazyVGrid(columns: columns, spacing: 10) {
                choice("Yes", detail: "Most nights") {
                    commit { flow.chooseWatch(wearsOne: true) }
                }
                choice("No", detail: "Just my phone") {
                    commit { flow.chooseWatch(wearsOne: false) }
                }
            }
        case .healthDetails:
            OnboardingHealthDetailsView(fields: flow.missingHealthFields,
                metric: flow.answers.unitsAreMetric, onSave: { details in
                    commit { flow.submitHealthDetails(details) }
                }, onSkip: { commit { flow.skipHealthDetails() } })
        case .obstacles:
            VStack(spacing: 14) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(Obstacle.allCases, id: \.self) { obstacle in
                        choice(obstacle.title, symbol: obstacle.symbol,
                               selected: flow.answers.obstacles.contains(obstacle)) {
                            Haptics.decided()
                            flow.toggleObstacle(obstacle)
                        }
                    }
                    // "Nothing" sits among the choices, not as a Skip in the footer.
                    // This and the injuries question are the same question twice, and
                    // they used to disagree about where the way out was: a grey Skip
                    // under one, a None among the choices of the other, so the next
                    // screen moved the button somebody had just learned to look for.
                    choice("Nothing") { commit { flow.confirmObstacles(none: true) } }
                }
                doneRow(enabled: !flow.answers.obstacles.isEmpty) {
                    commit { flow.confirmObstacles() }
                }
            }
        case .units:
            LazyVGrid(columns: columns, spacing: 10) {
                choice("Pounds", detail: "lb") { commit { flow.chooseUnits(metric: false) } }
                choice("Kilos", detail: "kg") { commit { flow.chooseUnits(metric: true) } }
            }
        case .health:
            DisclosureGroup("Health data we use") {
                Text("Sleep and heart metrics guide recovery. Activity and workouts guide training. Height, age, biological sex, body measurements, and logged food, water, caffeine, and alcohol add context. Daylight and mindful sessions support sleep and recovery coaching. You choose which to share in Health.")
                    .font(.subheadline).foregroundStyle(Tokens.textTertiary)
                    .padding(.vertical, 8)
            }
            .font(.subheadline).tint(Tokens.messageOutgoing)
            Button(action: connect) {
                Text(connecting ? "Opening Health…" : "Connect Health")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Tokens.messageOnOutgoing)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Tokens.messageOutgoing, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(connecting)
            Button("Not now") {
                model.skipHealthConnection()
                flow.skipHealth(profile: model.effectiveHealthProfile)
            }
            .font(.subheadline).frame(minHeight: 44).frame(maxWidth: .infinity)
            .tint(Tokens.messageOutgoing).disabled(connecting)
        case .weight:
            VStack(spacing: 12) {
                Text(weightLabel)
                    .font(.largeTitle.weight(.semibold)).monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Tokens.textPrimary)
                Stepper(value: $weightEntry, in: weightRange, step: 1) { EmptyView() }
                    .labelsHidden().ticksOnChange(weightEntry)
                confirmChoice("Use \(weightLabel)") {
                    commit { flow.recordWeight(weightLabel) }
                    model.recordOnboardingWeight(weightEntry,
                                                 metric: flow.answers.unitsAreMetric)
                }
                Button("Skip") { commit { flow.skipWeight() } }
                    .font(.subheadline).frame(minHeight: 44).frame(maxWidth: .infinity)
                    .tint(Tokens.messageOutgoing)
            }
        case .notifications:
            VStack(spacing: 12) {
                confirmChoice("Go ahead") {
                    Task {
                        // Asked here, so the system sheet lands on somebody who has just
                        // read what it is for rather than on a stranger.
                        await notifications.enable()
                        commit { flow.chooseNotifications(allowed: true) }
                    }
                }
                Button("Not now") { commit { flow.chooseNotifications(allowed: false) } }
                    .font(.subheadline).frame(minHeight: 44).frame(maxWidth: .infinity)
                    .tint(Tokens.messageOutgoing)
            }
        case .ready:
            // No menu of questions. Somebody who has just answered eight of them does
            // not have a ninth ready, and asking for one holds them at the door of an
            // app they have not seen yet. The same four starters are waiting in the
            // chat for whenever they do have something.
            VStack(spacing: 14) {
                foundingWelcome
                Button("Let's go") { complete() }
                .font(.body.weight(.semibold))
                .foregroundStyle(Tokens.messageOnOutgoing)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Tokens.messageOutgoing, in: Capsule())
                    .buttonStyle(.plain)
            }
        case .reading:
            EmptyView()
        }
    }

    private var weightRange: ClosedRange<Double> {
        flow.answers.unitsAreMetric ? 30...250 : 66...550
    }

    private var weightLabel: String {
        let unit = flow.answers.unitsAreMetric ? "kg" : "lb"
        return "\(Int(weightEntry)) \(unit)"
    }

    /// The same filled capsule the health step uses, so a confirmation looks the same
    /// wherever it appears in the flow.
    private func confirmChoice(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.body.weight(.semibold))
                .foregroundStyle(Tokens.messageOnOutgoing)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Tokens.messageOutgoing, in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }

    private func choice(_ title: String, detail: String? = nil, symbol: String? = nil,
                        selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selected()
            action()
        } label: {
            HStack(alignment: .center, spacing: 9) {
                if let symbol {
                    Image(systemName: selected ? "checkmark" : symbol)
                        .font(.subheadline)
                        .frame(width: 20)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.medium))
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(Tokens.textTertiary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Tokens.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(selected ? Tokens.messageOutgoing.opacity(0.10) : Tokens.surface,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(selected ? Tokens.messageOutgoing : Tokens.messageOutgoing.opacity(0.30), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 12) {
            ReadingArt(size: 150, isDone: connectionDone).frame(maxWidth: .infinity)
            if connectionDone {
                Text("Health connected")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Tokens.textPrimary)
                    .frame(maxWidth: .infinity)
            } else {
                ThinkingPill(label: "Checking Health")
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func commit(_ action: () -> Void) {
        guard settled else { return }
        Haptics.decided()
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9)) {
            action()
            visibleCount += 1
            receiptAnswerID = flow.turns.last(where: \.isUser)?.id
            deliveryStatus = "Sent"
        }
        OnboardingDraft.save(flow)
    }

    /// Put a resumed conversation on screen whole rather than replaying it.
    ///
    /// The reveal animation exists for a turn that just arrived. Running it over eight
    /// answers somebody gave yesterday would make them watch their own onboarding back.
    private func resumeIfSaved() {
        guard !flow.turns.isEmpty, visibleCount == 0 else { return }
        visibleCount = flow.turns.count
        reactedAnswers = Set(flow.turns.filter { $0.isUser && $0.reaction != nil }.map(\.id))
        receiptAnswerID = flow.turns.last(where: \.isUser)?.id
        // No time on a resumed conversation. It used to stamp the current one, so an
        // answer given at 1:19 read "Read 1:21" after a relaunch and "Read 1:24" after
        // the next: a tester watched the timestamps climb on messages nobody had sent
        // and said the chat felt like it was replaying itself. We do not know when it
        // was read, so we do not say.
        deliveryStatus = "Read"
    }

    private func scrollAfterLayout(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            scroll(proxy)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        if reduceMotion { proxy.scrollTo("latest", anchor: .bottom) }
        else { withAnimation(.easeOut(duration: 0.4)) { proxy.scrollTo("latest", anchor: .bottom) } }
    }

    private func connect() {
        guard !connecting else { return }
        connecting = true
        connectionDone = false
        Task {
            var hasFreshHealthData = false
            var began: ContinuousClock.Instant?
            await model.refresh(seedSimulatorData: false, requestHealthAccess: true, onAuthorized: {
                flow.beginReading()
                began = .now
            }, onHealthRead: { hasFreshHealthData = $0 })
            Analytics.record(.healthConnected, ["has_data": hasFreshHealthData])
            // Authorization errors still reach the honest empty-data result.
            if began == nil { flow.beginReading(); began = .now }
            if let began {
                let remaining = Duration.milliseconds(1300) - began.duration(to: .now)
                if remaining > .zero { try? await Task.sleep(for: remaining) }
            }
            if hasFreshHealthData {
                connectionDone = true
                Haptics.committed()
                // The Rive transition takes 300ms. Let the settled check read before
                // the thread moves on; Reduce Motion gets the static confirmation.
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 600 : 1100))
            }
            model.startBackgroundDelivery()
            flow.knowsWeight = model.latestWeight != nil
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) {
                flow.finishReading(hasHealthData: model.hasOnboardingHealthData,
                                   // Days that actually had something in them.
                                   // `dailySeries` returns a row per day for all 180
                                   // whether or not anything was recorded, so this was
                                   // always exactly 180, and everybody who granted
                                   // access, including someone whose watch arrived
                                   // yesterday, was told "180 nights, read".
                                   daysRead: model.series.filter(\.hasReadinessData).count,
                                   profile: model.effectiveHealthProfile)
                // The reading/done beat already supplied the pause. Replace it with
                // Jett's reply together so the thread never jumps to an empty gap.
                visibleCount = flow.turns.count
                connecting = false
            }
        }
    }

    private func complete() {
        model.completeOnboarding(flow.answers, in: context)
        // Built from what was just answered rather than asked for again on the next
        // screen. Nil when somebody ruled out every movement, which is the one case
        // where the app genuinely has nothing safe to suggest.
        model.installStarterProgram(in: context)
        model.pendingOnboardingConversation = flow.turns.map {
            CoachMessage(role: $0.isUser ? .user : .assistant, text: $0.text, reaction: $0.reaction)
        }
        Haptics.committed()
        OnboardingDraft.clear()
        model.finishOnboarding()
    }
}

/// Half an answered onboarding, kept across launches.
///
/// It used to die with the app. A tester force quit twice while stuck on a question and
/// came back both times to "Hey, I'm Jett" with eight answers gone, which is the point
/// most people stop reinstalling an app rather than answer it all a third time.
///
/// Not saved during the health read, which is the one step that is a running task rather
/// than a question: resuming into it would be resuming into a spinner that nothing is
/// feeding. The save from the question before it stands, so a crash there comes back to
/// the last thing somebody actually answered.
enum OnboardingDraft {
    private static let key = "onboarding.draft"

    static func save(_ flow: OnboardingConversation) {
        guard flow.step != .reading, flow.step != .ready else { return }
        guard let data = try? JSONEncoder().encode(flow) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func restore() -> OnboardingConversation? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let flow = try? JSONDecoder().decode(OnboardingConversation.self, from: data),
              !flow.turns.isEmpty
        else { return nil }
        return flow
    }

    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
