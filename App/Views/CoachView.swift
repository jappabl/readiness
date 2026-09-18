import SwiftUI
import SwiftData

/// The coach entry: a mark in the corner that retracts while you read, and a standard
/// sheet when you tap it.
///
/// The coach covers the screen edge to edge and is itself translucent, so the app
/// behind blurs through it. Dismiss by dragging down or tapping the empty area —
/// the grabber says which.
struct CoachLayer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isOpen = false

    var body: some View {
        GeometryReader { geometry in
            button
                .padding(.trailing, Tokens.screenMargin)
                .padding(.bottom, 98)
                .frame(width: geometry.size.width, height: geometry.size.height,
                       alignment: .bottomTrailing)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22),
                   value: model.coachEntryExpanded)
        // fullScreenCover, not sheet: the large detent always leaves an inset strip of
        // the parent at the top, and iOS lays a dimming layer under a sheet — so the
        // material ends up blurring flat grey instead of the app.
        .fullScreenCover(isPresented: $isOpen) {
            CoachSheet()
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var button: some View {
        Button { Haptics.light(); isOpen = true } label: {
            Image("LogoMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(Tokens.accent)
                .frame(width: 54, height: 54)
                .glassSurface(Circle())
                .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .opacity(model.coachEntryExpanded ? 1 : 0)
        .scaleEffect(model.coachEntryExpanded ? 1 : 0.7)
        .allowsHitTesting(model.coachEntryExpanded)
        .accessibilityLabel("Ask Coach Jett")
    }
}

// MARK: - The sheet

struct CoachSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [CoachMessage] = []
    @State private var draft = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @State private var proposal: CoachToolCall?
    @State private var appliedNote: String?
    @FocusState private var composerFocused: Bool

    private let provider = ClaudeCoachProvider()

    var body: some View {
        VStack(spacing: 0) {
            grabber
            title
            if messages.isEmpty && errorMessage == nil {
                suggestions
            } else {
                transcript
            }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
        .ignoresSafeArea(.container, edges: .bottom)
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 90 { dismiss() }
                })
    }

    private var grabber: some View {
        Capsule()
            .fill(Color.primary.opacity(0.22))
            .frame(width: 36, height: 5)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .accessibilityLabel("Drag down to close")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { dismiss() }
    }

    private var title: some View {
        VStack(spacing: 10) {
            Image("LogoMark")
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(width: 30, height: 30)
                .foregroundStyle(Tokens.accent)
                .frame(width: 66, height: 66)
                .background(Tokens.accent.opacity(0.12), in: Circle())

            VStack(spacing: 4) {
                Text("Coach Jett")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Tokens.textPrimary)
                Text(greeting)
                    .font(.system(size: 15))
                    .foregroundStyle(Tokens.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
        .padding(.top, 26)
        .padding(.bottom, 22)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Jett opens on what is actually true about today, not a stock hello.
    private var greeting: String {
        guard let recommendation = model.recommendation else {
            return "Ask me anything about your training."
        }
        switch recommendation.state {
        case .push:     return "Good day to train. Ask me anything."
        case .maintain: return "Nothing's off today. What's on your mind?"
        case .reduce:   return "You're under baseline today. Ask me how to adjust."
        case .recover:  return "Rough morning. Ask me what's driving it."
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Self.starters, id: \.self) { prompt in
                Button { send(prompt) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 14))
                            .foregroundStyle(Tokens.accent)
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

    static let starters = [
        "Why is my recovery down today?",
        "Can I still train legs?",
        "What changed this week?",
    ]

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                    if let proposal { proposalCard(proposal) }
                    if let appliedNote {
                        Label(appliedNote, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Tokens.accent)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 14))
                            .foregroundStyle(Tokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.last?.text) {
                guard let last = messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
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
                    .font(.system(size: 14))
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
        HStack(spacing: 6) {
            TextField("Ask about your health or training", text: $draft, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .disabled(isStreaming)
                .padding(.leading, 18)
                .padding(.vertical, 14)

            Button {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                draft = ""
                send(text)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Tokens.onAccent)
                    .frame(width: 34, height: 34)
                    .background(canSend ? Tokens.accent : Color.primary.opacity(0.14), in: Circle())
            }
            .disabled(!canSend)
            .padding(.trailing, 6)
            .accessibilityLabel("Send")
        }
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
        .padding(.top, 6)
    }

    private var canSend: Bool {
        !isStreaming && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send(_ text: String) {
        guard !text.isEmpty, !isStreaming else { return }
        errorMessage = nil

        guard let coachContext = model.coachContext(context: context) else {
            errorMessage = "Still reading your health data. Try again in a moment."
            return
        }

        messages.append(CoachMessage(role: .user, text: text))
        let reply = CoachMessage(role: .assistant, text: "")
        messages.append(reply)
        isStreaming = true

        Task {
            do {
                let events = provider.stream(
                    messages: messages.dropLast().map { $0 },
                    context: coachContext,
                    applyTool: { call in
                        await MainActor.run { proposal = call }
                        // Jett is told it was proposed, not applied, so it describes the
                        // change as a suggestion rather than a done deal.
                        return "Shown to the user as a suggestion: "
                            + "\(Copy.describe(call.adjustment)). Awaiting their approval."
                    })

                for try await event in events {
                    switch event {
                    case .text(let chunk):
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

struct MessageBubble: View {
    let message: CoachMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 44) }
            Text(message.text.isEmpty ? "…" : message.text)
                .font(.system(size: 16))
                .foregroundStyle(message.role == .user ? Tokens.onAccent : Tokens.textPrimary)
                .padding(.vertical, 11).padding(.horizontal, 15)
                .background(message.role == .user
                            ? AnyShapeStyle(Tokens.accent)
                            : AnyShapeStyle(Color.primary.opacity(0.06)),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
            if message.role == .assistant { Spacer(minLength: 44) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "You" : "Jett"): \(message.text)")
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
