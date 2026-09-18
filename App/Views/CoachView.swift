import SwiftUI
import SwiftData

// MARK: - The layer

/// A pill that grows into the coach, rather than a screen that appears beside it.
/// Closed it floats above the tab bar; open it becomes a panel over a blurred app.
/// One object, one skin, one transformation.
struct CoachLayer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isOpen = false
    @State private var messages: [CoachMessage] = []
    @State private var draft = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?
    @State private var contentHeight: CGFloat = 0
    @FocusState private var composerFocused: Bool

    /// The panel never grows past this, however long the conversation runs.
    private let maximumPanelHeight: CGFloat = 560

    private let provider = ClaudeCoachProvider()

    var body: some View {
        ZStack(alignment: .bottom) {
            if isOpen {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { close() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Close coach")
            }

            surface
                .padding(.horizontal, isOpen ? 10 : Tokens.screenMargin)
                .padding(.bottom, isOpen ? 8 : 96)
        }
        .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86),
                   value: isOpen)
    }

    // MARK: - The one surface

    private var surface: some View {
        VStack(spacing: 0) {
            if isOpen { conversation } else { pillLabel }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isOpen ? min(maximumPanelHeight, contentHeight) : 54)
        .glassSurface(RoundedRectangle(cornerRadius: isOpen ? 30 : 27, style: .continuous))
        .shadow(color: .black.opacity(isOpen ? 0.16 : 0.10),
                radius: isOpen ? 28 : 14, x: 0, y: isOpen ? 10 : 5)
        .contentShape(RoundedRectangle(cornerRadius: isOpen ? 30 : 27, style: .continuous))
        .onTapGesture { if !isOpen { open() } }
    }

    private var pillLabel: some View {
        HStack(spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Tokens.accent)
            Text("Ask Coach Gavin")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Tokens.textPrimary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.up")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.textSecondary)
        }
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ask Coach Gavin")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Opened

    private var conversation: some View {
        VStack(spacing: 0) {
            grabber
            transcript
            composer
        }
        .transition(.opacity)
    }

    /// Reports the natural height of the conversation so the panel can hug it.
    private struct HeightKey: PreferenceKey {
        static var defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private var grabber: some View {
        HStack {
            Text("Coach Gavin")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tokens.textPrimary)
            Spacer()
            Button { close() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Tokens.ringTrack.opacity(0.6), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty { starters }
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
                        .background(Tokens.surface.opacity(0.92),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: HeightKey.self,
                                           // header + composer chrome
                                           value: geometry.size.height + 118)
                })
            }
            .scrollBounceBehavior(.basedOnSize)
            .onPreferenceChange(HeightKey.self) { contentHeight = $0 }
            .onChange(of: messages.last?.text) {
                guard let last = messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var starters: some View {
        VStack(spacing: 8) {
            ForEach(Self.starters, id: \.self) { prompt in
                Button { send(prompt) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "sparkles").font(.system(size: 13))
                            .foregroundStyle(Tokens.accent)
                        Text(prompt).font(.system(size: 15))
                            .foregroundStyle(Tokens.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tokens.surface.opacity(0.92),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    static let starters = [
        "Why is my recovery down today?",
        "Can I still train legs?",
        "What changed this week?",
    ]

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask about your health or training", text: $draft, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .padding(.vertical, 11).padding(.horizontal, 15)
                .background(Tokens.surface.opacity(0.95), in: Capsule())
                .disabled(isStreaming)

            Button {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                draft = ""
                send(text)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tokens.onAccent)
                    .frame(width: 42, height: 42)
                    .background(canSend ? Tokens.accent : Tokens.ringTrack, in: Circle())
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }

    private var canSend: Bool {
        !isStreaming && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Behaviour

    private func open() {
        isOpen = true
    }

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

// MARK: - Bubbles

struct MessageBubble: View {
    let message: CoachMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text.isEmpty ? "…" : message.text)
                .font(.system(size: 15))
                .foregroundStyle(message.role == .user ? Tokens.onAccent : Tokens.textPrimary)
                .padding(.vertical, 11).padding(.horizontal, 15)
                .background(message.role == .user ? AnyShapeStyle(Tokens.accent)
                                                  : AnyShapeStyle(Tokens.surface.opacity(0.92)),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .fixedSize(horizontal: false, vertical: true)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "You" : "Gavin"): \(message.text)")
    }
}

// MARK: - Glass

extension View {
    /// Liquid Glass where the OS has it, a material where it does not.
    @ViewBuilder
    func glassSurface(_ shape: some InsettableShape) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.clear, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
        }
    }
}
