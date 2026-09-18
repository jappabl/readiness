import SwiftUI
import SwiftData

struct CoachView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @State private var messages: [CoachMessage] = []
    @State private var draft = ""
    @State private var isStreaming = false
    @State private var errorMessage: String?

    private let provider = ClaudeCoachProvider()

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                transcript
                composer
            }
        }
        .navigationTitle("Coach")
        .toolbarBackground(Tokens.canvas, for: .navigationBar)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty { opener }
                    ForEach(messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }
                    if let errorMessage {
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13)).foregroundStyle(Tokens.negative)
                            Text(errorMessage)
                                .font(.system(size: 14))
                                .foregroundStyle(Tokens.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .bevelCard(padding: 13)
                    }
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.vertical, 12)
            }
            .onChange(of: messages.last?.text) {
                guard let last = messages.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var opener: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ask about your training").sectionHeading()
                Text("The coach sees today's measurements, your baselines, your program and "
                     + "your recent sessions. Nothing else, and it won't guess.")
                    .font(.system(size: 14)).foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ListCard {
                ForEach(Array(Self.starters.enumerated()), id: \.element) { index, prompt in
                    if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                    Button { send(prompt) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles").font(.system(size: 13))
                                .foregroundStyle(Tokens.accent)
                            Text(prompt)
                                .font(.system(size: 15))
                                .foregroundStyle(Tokens.textPrimary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right").font(.system(size: 12))
                                .foregroundStyle(Tokens.textSecondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    static let starters = [
        "Why is my recovery down today?",
        "Can I still train legs?",
        "What changed this week?",
    ]

    private var composer: some View {
        VStack(spacing: 8) {
            Divider().overlay(Tokens.hairline)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about your health or training", text: $draft, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 12).padding(.horizontal, 15)
                    .background(Tokens.surface, in: Capsule())
                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                    .disabled(isStreaming)

                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft = ""
                    send(text)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Tokens.onAccent)
                        .frame(width: 44, height: 44)
                        .background(canSend ? Tokens.accent : Tokens.ringTrack, in: Circle())
                        .shadow(color: canSend ? Tokens.accent.opacity(0.3) : .clear,
                                radius: 8, x: 0, y: 3)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.bottom, 8)
        }
        .background(Tokens.canvas)
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
                for try await chunk in provider.stream(messages: messages.dropLast()
                                                        .map { $0 }, context: coachContext) {
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
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text.isEmpty ? "…" : message.text)
                .font(.system(size: 15))
                .foregroundStyle(message.role == .user ? Tokens.onAccent : Tokens.textPrimary)
                .padding(.vertical, 11).padding(.horizontal, 15)
                .background(message.role == .user ? Tokens.accent : Tokens.surface,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(message.role == .user ? 0 : 0.05),
                        radius: 8, x: 0, y: 2)
                .fixedSize(horizontal: false, vertical: true)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "You" : "Coach"): \(message.text)")
    }
}
