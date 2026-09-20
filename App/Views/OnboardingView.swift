import SwiftUI
import SwiftData

/// The first part of the same conversation that continues in CoachSheet.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var flow = OnboardingConversation()
    @State private var visibleCount = 0
    @State private var connecting = false
    @State private var connectionDone = false
    @State private var draft = ""
    @State private var showingSharing = false
    @State private var pendingQuestion = ""
    @State private var startedAt = Date()
    @State private var receiptAnswerID: Int?
    @State private var deliveryStatus = ""
    @State private var reactedAnswers: Set<Int> = []

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
                        if settled { responses }
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if flow.step == .ready && settled {
                VStack(spacing: 0) {
                    CoachComposer(draft: $draft, isStreaming: false, onSend: finish)
                    Text("Jett uses AI. You choose what to share before your first reply.")
                        .font(.caption2)
                        .foregroundStyle(Tokens.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 6)
                }
                .background(Tokens.messageCanvas)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.messageCanvas.ignoresSafeArea())
        .sheet(isPresented: $showingSharing, onDismiss: {
            if !model.coachSharingAllowed { draft = pendingQuestion }
        }) {
            CoachSharingSheet(onAllow: {
                model.coachSharingAllowed = true
                showingSharing = false
                complete(pendingQuestion)
            }, onCancel: { showingSharing = false })
        }
        .task(id: flow.turns.count) {
            visibleCount = min(visibleCount, flow.turns.count)
            do {
                while visibleCount < flow.turns.count {
                    let answer = flow.turns.prefix(visibleCount).last
                    if let answer, answer.isUser {
                        // Acknowledge the tap first, then give the reply a readable beat.
                        try await Task.sleep(for: .milliseconds(250))
                        deliveryStatus = "Delivered"
                        try await Task.sleep(for: .milliseconds(550))
                        deliveryStatus = "Read " + Date().formatted(date: .omitted, time: .shortened)
                        try await Task.sleep(for: .milliseconds(180))
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                            _ = reactedAnswers.insert(answer.id)
                        }
                        let replyLength = flow.turns[visibleCount].text.count
                        let remaining = min(650, max(270, replyLength * 7))
                        try await Task.sleep(for: .milliseconds(remaining))
                    } else {
                        try await Task.sleep(for: .milliseconds(700))
                    }
                    guard !Task.isCancelled else { return }
                    Haptics.replyBegan()
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                        visibleCount += 1
                    }
                    Haptics.replyEnded()
                }
            } catch { return }
        }
    }

    @ViewBuilder
    private func turnView(_ turn: OnboardingConversation.Turn) -> some View {
        let message = CoachMessage(role: turn.isUser ? .user : .assistant, text: turn.text,
                                   reaction: reactedAnswers.contains(turn.id) ? turn.reaction : nil)
        let editable = turn.id == flow.latestEditableAnswerID && settled && !connecting
        if turn.isUser {
            Button {
                guard editable else { return }
                Haptics.light()
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    flow.editAnswer(id: turn.id)
                    visibleCount = flow.turns.count
                    receiptAnswerID = nil
                }
            } label: {
                answerWithReceipt(message, turnID: turn.id, editable: editable, reservesReactionSpace: turn.reaction != nil)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(editable)
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

    private func answerWithReceipt(_ message: CoachMessage, turnID: Int, editable: Bool,
                                   reservesReactionSpace: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            CoachTurnView(message: message, reservesReactionSpace: reservesReactionSpace)
            if receiptAnswerID == turnID {
                HStack(spacing: 5) {
                    Text(deliveryStatus)
                    if editable { Text("·").accessibilityHidden(true); Text("Edit") }
                }
                .font(.caption2)
                .foregroundStyle(Tokens.textTertiary)
                .contentTransition(.opacity)
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
                if flow.answers.limitations?.isEmpty == false {
                    Button("Done") { commit { flow.confirmLimitations() } }
                        .font(.body.weight(.semibold))
                        .frame(minHeight: 44).frame(maxWidth: .infinity, alignment: .trailing)
                        .tint(Tokens.messageOutgoing)
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
                }
                Button(flow.answers.obstacles.isEmpty ? "Skip" : "Done") {
                    commit { flow.confirmObstacles() }
                }
                .font(.body.weight(.semibold))
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .tint(Tokens.messageOutgoing)
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
        case .ready:
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(OnboardingConversation.starterQuestions, id: \.self) { question in
                    choice(question) {
                        Haptics.decided()
                        draft = question
                    }
                }
            }
            Button("Explore the app first") { complete(nil) }
                .font(.subheadline).frame(minHeight: 44).frame(maxWidth: .infinity)
                .tint(Tokens.messageOutgoing)
        case .reading:
            EmptyView()
        }
    }

    private func choice(_ title: String, detail: String? = nil, symbol: String? = nil,
                        selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
    }

    private func scrollAfterLayout(_ proxy: ScrollViewProxy) {
        Task { @MainActor in
            await Task.yield()
            scroll(proxy)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        if reduceMotion { proxy.scrollTo("latest", anchor: .bottom) }
        else { withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("latest", anchor: .bottom) } }
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
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
                flow.finishReading(hasHealthData: model.hasOnboardingHealthData,
                                   daysRead: model.series.count,
                                   profile: model.effectiveHealthProfile)
                // The reading/done beat already supplied the pause. Replace it with
                // Jett's reply together so the thread never jumps to an empty gap.
                visibleCount = flow.turns.count
                connecting = false
            }
        }
    }

    private func finish(_ text: String) {
        guard flow.step == .ready, settled else { return }
        guard model.coachSharingAllowed else {
            pendingQuestion = text
            showingSharing = true
            return
        }
        complete(text)
    }

    private func complete(_ text: String?) {
        model.completeOnboarding(flow.answers, in: context)
        model.pendingOnboardingConversation = flow.turns.map {
            CoachMessage(role: $0.isUser ? .user : .assistant, text: $0.text, reaction: $0.reaction)
        }
        model.pendingCoachMessage = text
        Haptics.committed()
        model.finishOnboarding()
    }
}
