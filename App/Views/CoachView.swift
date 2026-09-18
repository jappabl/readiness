import SwiftUI
import SwiftData

/// A mark that grows into the coach. Closed it is a small circle that retracts while
/// you read; open it is a translucent panel over a blurred app, so tapping anywhere
/// outside obviously dismisses it.
struct CoachLayer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isOpen = false
    @State private var messages: [CoachMessage] = []
    @State private var draft = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @FocusState private var composerFocused: Bool

    private let provider = ClaudeCoachProvider()

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottomTrailing) {
                if isOpen { backdrop }

                if isOpen {
                    panel(height: geometry.size.height * 0.74)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    button
                        .padding(.trailing, Tokens.screenMargin)
                        .padding(.bottom, 98)
                }
            }
            // GeometryReader lays its content out top-leading, so the stack has to be
            // told to fill it before bottomTrailing means anything.
            .frame(width: geometry.size.width, height: geometry.size.height,
                   alignment: .bottomTrailing)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.40, dampingFraction: 0.85),
                   value: isOpen)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22),
                   value: model.coachEntryExpanded)
    }

    // MARK: - Closed

    /// Small, cornered, and out of the way. It retracts on the way down the page and
    /// comes back when you stop or scroll up.
    private var button: some View {
        Button { open() } label: {
            Image("LogoMark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .foregroundStyle(Tokens.accent)
                .frame(width: 54, height: 54)
                .glassSurface(Circle())
                .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .opacity(model.coachEntryExpanded ? 1 : 0)
        .scaleEffect(model.coachEntryExpanded ? 1 : 0.7)
        .offset(y: model.coachEntryExpanded ? 0 : 14)
        .allowsHitTesting(model.coachEntryExpanded)
        .accessibilityLabel("Ask Coach Gavin")
    }

    // MARK: - Open

    /// Deliberately see-through. A solid sheet reads as a screen you have to dismiss
    /// with a control; a blurred one reads as something you can tap past.
    private var backdrop: some View {
        Rectangle()
            .fill(.regularMaterial)
            .ignoresSafeArea()
            .transition(.opacity)
            .onTapGesture { close() }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Close coach")
    }

    private func panel(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
            if messages.isEmpty && errorMessage == nil {
                suggestions
            } else {
                transcript
            }
            composer
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.14), radius: 26, x: 0, y: 10)
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image("LogoMark")
                .renderingMode(.template)
                .resizable().scaledToFit()
                .frame(width: 18, height: 18)
                .foregroundStyle(Tokens.accent)
            Text("Coach Gavin")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Tokens.textPrimary)
            Spacer()
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Tokens.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    /// Spread down the body rather than stacked at the top, so the empty state uses
    /// the room the conversation will later need.
    private var suggestions: some View {
        VStack(spacing: 0) {
            ForEach(Self.starters, id: \.self) { prompt in
                Spacer(minLength: 10)
                Button { send(prompt) } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
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
            Spacer(minLength: 10)
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
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13)).foregroundStyle(Tokens.negative)
                            Text(errorMessage)
                                .font(.system(size: 14)).foregroundStyle(Tokens.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: messages.last?.text) {
                guard let last = messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Ask about your health or training", text: $draft, axis: .vertical)
                .font(.system(size: 16))
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .disabled(isStreaming)
                .padding(.leading, 18)
                .padding(.trailing, 6)
                .padding(.vertical, 13)

            Button {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                draft = ""
                send(text)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Tokens.onAccent)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Tokens.accent : Color.primary.opacity(0.12), in: Circle())
            }
            .disabled(!canSend)
            .padding(.trailing, 7)
            .accessibilityLabel("Send")
        }
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .padding(.top, 6)
    }

    private var canSend: Bool {
        !isStreaming && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Behaviour

    private func open() { isOpen = true }

    private func close() {
        composerFocused = false
        isOpen = false
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
                .font(.system(size: 15))
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
        .accessibilityLabel("\(message.role == .user ? "You" : "Gavin"): \(message.text)")
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
