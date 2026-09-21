import SwiftUI
import SwiftData

// MARK: - The sheet

struct CoachSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(Subscriptions.self) private var store
    @Environment(\.modelContext) private var context

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [CoachMessage] = []
    @State private var draft = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @State private var proposal: CoachToolCall?
    @State private var toolStep: String?
    @State private var showingPaywall = false
    @State private var showingSharing = false
    @State private var pendingQuestion = ""
    @State private var appliedNote: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var continuesOnboarding = false
    @Environment(\.dynamicTypeSize) private var typeSize

    /// With no key configured, a debug build rehearses instead of failing — the UI is
    /// the thing being worked on far more often than the model is.
    private var provider: CoachProvider {
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        let live = ClaudeCoachProvider(unitsAreMetric: profile?.unitsAreMetric ?? false)
        #if DEBUG
        return continuesOnboarding || live.isConfigured ? live : RehearsalCoachProvider()
        #else
        return live
        #endif
    }

    var body: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            CoachContactHeader(onBack: { dismiss() },
                               isThinking: isStreaming && (messages.last?.text.isEmpty ?? true),
                               isSpeaking: isStreaming && !(messages.last?.text.isEmpty ?? true))
            // The flash belongs over the conversation, not over Jett's own face.
            Group {
                if messages.isEmpty && errorMessage == nil {
                    suggestions
                } else {
                    transcript
                }
            }
            .memoryFlash($model.memoryFlash)
            if allowance.showsRemaining, let left = allowance.remaining {
                Button { showingPaywall = true } label: {
                    Text(left == 0
                         ? "You've used your free answers. See plans"
                         : "\(Copy.count(left, "free answer")) left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tokens.textSecondary)
                        .padding(.bottom, 2)
                }
                .buttonStyle(.plain)
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.messageCanvas)
        .ignoresSafeArea(.container, edges: .bottom)
        .sheet(isPresented: $showingSharing, onDismiss: {
            if !model.coachSharingAllowed { draft = pendingQuestion }
        }) {
            CoachSharingSheet(onAllow: {
                model.coachSharingAllowed = true
                showingSharing = false
                send(pendingQuestion)
            }, onCancel: { showingSharing = false })
        }
        .task {
            if messages.isEmpty {
                messages = CoachTurn.recent(in: context).map(\.message)
            }
            guard let pending = model.pendingCoachMessage else { return }
            // Clear before sending so view recreation cannot submit a second request.
            model.pendingCoachMessage = nil
            continuesOnboarding = true
            messages = model.pendingOnboardingConversation
            model.pendingOnboardingConversation = []
            send(pending)
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView { showingPaywall = false }
        }
    }

    /// The opening, which is already the conversation.
    ///
    /// It used to be four grey rows with a sparkle and an arrow on each: a menu bolted
    /// to the top of a chat, in a style that appears nowhere else in the app. Jett says
    /// hello in his own bubble instead and the questions sit under it as choices, the
    /// same shape onboarding uses, so the first screen looks like the second one.
    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CoachTurnView(message: CoachMessage(role: .assistant, text: Self.opener),
                              revealsWords: !reduceMotion)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Self.starters, id: \.self) { prompt in
                        starter(prompt)
                    }
                }
            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.top)
    }

    /// The same two columns onboarding uses, and the same chip, down to the border.
    /// The last thing somebody saw before the app opened was this exact grid.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10),
              count: typeSize.isAccessibilitySize ? 1 : 2)
    }

    private func starter(_ prompt: String) -> some View {
        Button {
            Haptics.decided()
            send(prompt)
        } label: {
            HStack(spacing: 0) {
                Text(prompt)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Tokens.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Tokens.messageOutgoing.opacity(0.30), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    /// Short, and open, because most people do not arrive with one of the four in mind.
    static let opener = "Hey. What's up?"

    static let starters = OnboardingConversation.starterQuestions

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        CoachTurnView(message: message).id(message.id)
                    }
                    // A container with nothing in it reads as a failure, so the empty
                    // reply is a word rather than an empty bubble.
                    if isStreaming, messages.last?.text.isEmpty != false {
                        ThinkingPill().id("thinking")
                    }
                    if let step = toolStep {
                        CoachStepRow(label: step, isRunning: proposal == nil)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    // Only a session change has a card. A memory has already happened
                    // by the time anything is drawn, and says so in passing instead.
                    if let proposal, let adjustment = proposal.adjustment {
                        proposalCard(proposal, adjustment)
                    }
                    if let appliedNote {
                        Label(appliedNote, systemImage: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(Tokens.accent)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(Tokens.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                    Color.clear.frame(height: 1).id("coachBottom")
                        .onAppear { proxy.scrollTo("coachBottom", anchor: .bottom) }
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.vertical, 10)
            }
            .conversationScrollAnchor()
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.text) {
                if reduceMotion { proxy.scrollTo("coachBottom", anchor: .bottom) }
                else { withAnimation { proxy.scrollTo("coachBottom", anchor: .bottom) } }
            }
            .onChange(of: errorMessage) {
                Task { @MainActor in
                    await Task.yield()
                    proxy.scrollTo("coachBottom", anchor: .bottom)
                }
            }
            .background {
                GeometryReader { geometry in
                    Color.clear.onChange(of: geometry.size.height) {
                        proxy.scrollTo("coachBottom", anchor: .bottom)
                    }
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: toolStep)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: proposal)
        }
    }

    /// Jett proposes; the user decides. The original session is never overwritten
    /// without an explicit tap.
    private func proposalCard(_ call: CoachToolCall,
                              _ adjustment: SessionAdjustment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Jett suggests", systemImage: "sparkle")
                .font(.system(size: 12, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Tokens.accent)

            Text(Copy.describe(adjustment))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !call.reason.isEmpty {
                Text(call.reason)
                    .font(.subheadline)
                    .foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button {
                    Haptics.committed()
                    model.coachAdjustment = adjustment
                    model.record(.modified)
                    appliedNote = "Applied to today's session"
                    proposal = nil
                } label: {
                    Text("Apply")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.onAction)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Tokens.action, in: Capsule())
                }
                .buttonStyle(PressableStyle())

                Button { proposal = nil } label: {
                    Text("Not now")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Tokens.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.accent.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Tokens.accent.opacity(0.28), lineWidth: 1))
    }

    private var composer: some View {
        CoachComposer(draft: $draft, isStreaming: isStreaming, onSend: send)
    }

    /// How many past turns travel with a question. The server allows sixteen; a
    /// conversation does not need them, and every one is paid for on every message.
    static let turnsSent = 8

    private func keep(_ message: CoachMessage) {
        // Onboarding's opening turns are staged in memory before anything is sent, and
        // writing them here would replay the whole script on the next launch.
        guard !continuesOnboarding else { return }
        context.insert(CoachTurn(role: message.role.rawValue, text: message.text,
                                 reaction: message.reaction?.rawValue ?? ""))
        try? context.save()
    }

    private var allowance: CoachAllowance {
        Paywall.allowance(used: model.coachMessagesUsed, isSubscribed: store.isSubscribed)
    }

    private func send(_ text: String) {
        guard !text.isEmpty, !isStreaming else { return }
        guard model.coachSharingAllowed else {
            pendingQuestion = text
            showingSharing = true
            return
        }
        let asked = CoachMessage(role: .user, text: text)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
            messages.append(asked)
        }
        keep(asked)
        // The wall lands where the value is, not before it: five real answers first.
        guard allowance.isAllowed else {
            Haptics.light()
            showingPaywall = true
            return
        }
        // Unlimited does not mean unlimited per second. A conversation never sees this.
        if let wait = model.burstDelay() {
            errorMessage = "One at a time. Try again in \(Int(wait))s."
            return
        }
        errorMessage = nil

        guard let coachContext = model.coachContext(context: context) else {
            errorMessage = "Still reading your health data. Try again in a moment."
            return
        }

        guard provider.isConfigured else {
            errorMessage = CoachError.notConfigured.localizedDescription
            return
        }
        model.recordCoachMessage()
        let reply = CoachMessage(role: .assistant, text: "")
        messages.append(reply)
        isStreaming = true
        toolStep = nil
        var hasSpoken = false

        Task {
            do {
                let events = provider.stream(
                    messages: Array(messages.dropLast().suffix(Self.turnsSent)),
                    context: coachContext,
                    applyTool: { call in
                        await MainActor.run {
                            switch call.intent {
                            case .adjust(let adjustment):
                                toolStep = "Adjusting today's session"
                                proposal = call
                                Haptics.decided()
                                // Jett is told it was proposed, not applied, so it
                                // describes the change as a suggestion, not a done deal.
                                return "Shown to the user as a suggestion: "
                                    + "\(Copy.describe(adjustment)). Awaiting their approval."
                            case .remember, .forget:
                                // Applied at once. A memory is a sentence they already
                                // said, and asking permission to keep it would be more
                                // intrusive than keeping it — what protects them is that
                                // the list is visible and deletable in Profile.
                                return model.applyMemory(call.intent)
                            }
                        }
                    })

                for try await event in events {
                    switch event {
                    case .text(let chunk):
                        // The tap lands when the answer starts, not when it is asked
                        // for — that is the moment the wait actually ended.
                        if !hasSpoken, !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            hasSpoken = true
                            Haptics.replyBegan()
                        }
                        if let index = messages.firstIndex(where: { $0.id == reply.id }) {
                            messages[index].text += chunk
                        }
                    case .toolCall:
                        break   // surfaced through applyTool
                    }
                }
            } catch {
                messages.removeAll { $0.id == reply.id && $0.text.isEmpty }
                errorMessage = error.localizedDescription
            }
            messages.removeAll { $0.id == reply.id && $0.text.isEmpty }
            if let answered = messages.first(where: { $0.id == reply.id }) { keep(answered) }
            isStreaming = false
            if hasSpoken { Haptics.replyEnded() }
        }
    }
}

/// A press should feel like a press.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension View {
    /// Liquid Glass where the OS has it, a material where it does not.
    @ViewBuilder
    func glassSurface(_ shape: some InsettableShape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
        }
    }
}
