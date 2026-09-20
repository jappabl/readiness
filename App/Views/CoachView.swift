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
        VStack(spacing: 0) {
            CoachContactHeader(onBack: { dismiss() },
                               isThinking: isStreaming && (messages.last?.text.isEmpty ?? true),
                               isSpeaking: isStreaming && !(messages.last?.text.isEmpty ?? true))
            if messages.isEmpty && errorMessage == nil {
                suggestions
            } else {
                transcript
            }
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

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.starters, id: \.self) { prompt in
                Button { send(prompt) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkle")
                            .font(.subheadline)
                            .foregroundStyle(Tokens.jettTint)
                        Text(prompt)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Tokens.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Tokens.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 15)
                    .background(Color.primary.opacity(0.05),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(PressableStyle())
            }
            // The room below belongs to the conversation, and dismisses on a tap.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
        }
        .padding(.horizontal, 20)
    }

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
                    if let proposal { proposalCard(proposal) }
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
    private func proposalCard(_ call: CoachToolCall) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Jett suggests", systemImage: "sparkle")
                .font(.system(size: 12, weight: .medium))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(Tokens.accent)

            Text(Copy.describe(call.adjustment))
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
                    model.coachAdjustment = call.adjustment
                    model.record(.modified)
                    appliedNote = "Applied to today's session"
                    proposal = nil
                } label: {
                    Text("Apply")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(Tokens.accent, in: Capsule())
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
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.24)) {
            messages.append(CoachMessage(role: .user, text: text))
        }
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
                    messages: messages.dropLast().map { $0 },
                    context: coachContext,
                    applyTool: { call in
                        await MainActor.run {
                            toolStep = "Adjusting today's session"
                            proposal = call
                            Haptics.decided()
                        }
                        // Jett is told it was proposed, not applied, so it describes the
                        // change as a suggestion rather than a done deal.
                        return "Shown to the user as a suggestion: "
                            + "\(Copy.describe(call.adjustment)). Awaiting their approval."
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
