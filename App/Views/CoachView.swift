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
        .navigationBarTitleDisplayMode(.inline)
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
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(Tokens.negative)
                            .fixedSize(horizontal: false, vertical: true)
                            .card()
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Ask about your training")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(Tokens.textPrimary)
            Text("The coach can see today's measurements, your baselines, your program and "
                 + "your recent sessions. It can't see anything else, and it won't guess.")
                .font(.subheadline).foregroundStyle(Tokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.starters, id: \.self) { prompt in
                    Button { send(prompt) } label: {
                        Text(prompt)
                            .font(.subheadline)
                            .foregroundStyle(Tokens.accent)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10).padding(.horizontal, 12)
                            .background(Tokens.surface,
                                        in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    static let starters = [
        "Why is my readiness down today?",
        "Can I still train legs?",
        "What changed this week?",
    ]

    private var composer: some View {
        VStack(spacing: 8) {
            Divider().overlay(Tokens.hairline)
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Ask about your health or training", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .padding(.vertical, 10).padding(.horizontal, 12)
                    .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 20))
                    .disabled(isStreaming)

                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft = ""
                    send(text)
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Tokens.onAccent)
                        .frame(width: 44, height: 44)
                        .background(Tokens.accent, in: Circle())
                }
                .disabled(isStreaming
                          || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.bottom, 8)
        }
        .background(Tokens.canvas)
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
                .font(.body)
                .foregroundStyle(message.role == .user ? Tokens.onAccent : Tokens.textPrimary)
                .padding(.vertical, 10).padding(.horizontal, 14)
                .background(message.role == .user ? Tokens.accent : Tokens.surface,
                            in: RoundedRectangle(cornerRadius: 16))
                .fixedSize(horizontal: false, vertical: true)
            if message.role == .assistant { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == .user ? "You" : "Coach"): \(message.text)")
    }
}
