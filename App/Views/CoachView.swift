import SwiftUI
import SwiftData

/// The coach entry: a mark in the corner that retracts while you read, and a standard
/// sheet when you tap it.
///
/// The sheet is a plain `.sheet` with detents rather than a bespoke panel. That buys
/// the grabber, drag-to-dismiss, tap-outside-to-dismiss, keyboard avoidance and the
/// translucent presentation background for free — all of which were hand-rolled, and
/// worse, before.
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
        .sheet(isPresented: $isOpen) {
            CoachSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
                .presentationCornerRadius(28)
        }
    }

    private var button: some View {
        Button { isOpen = true } label: {
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

    @State private var messages: [CoachMessage] = []
    @State private var draft = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @FocusState private var composerFocused: Bool

    private let provider = ClaudeCoachProvider()

    var body: some View {
        VStack(spacing: 0) {
            title
            if messages.isEmpty && errorMessage == nil {
                suggestions
            } else {
                transcript
            }
            composer
        }
    }

    private var title: some View {
        HStack(spacing: 9) {
            Image("LogoMark")
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(width: 17, height: 17)
                .foregroundStyle(Tokens.accent)
            Text("Coach Jett")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }

    /// Spread down the body so the empty state occupies the room a conversation will.
    private var suggestions: some View {
        VStack(spacing: 0) {
            ForEach(Self.starters, id: \.self) { prompt in
                Spacer(minLength: 12)
                Button { send(prompt) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.accent)
                        Text(prompt)
                            .font(.system(size: 16))
                            .foregroundStyle(Tokens.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 12)
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

    private var composer: some View {
        HStack(spacing: 6) {
            TextField("Ask about your health or training", text: $draft, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .disabled(isStreaming)
                .padding(.leading, 18)
                .padding(.vertical, 12)

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
        .background(Color.primary.opacity(0.06), in: Capsule())
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
                for try await chunk in provider.stream(messages: messages.dropLast().map { $0 },
                                                       context: coachContext) {
                    if let index = messages.firstIndex(where: { $0.id == reply.id }) {
                        messages[index].text += chunk
                    }
                }
            } catch {
                messages.removeAll { $0.id == reply.id && $0.text.isEmpty }
                errorMessage = error.localizedDescription
            }
            isStreaming = false
        }
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
