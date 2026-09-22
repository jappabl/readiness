import SwiftUI

/// Messages-style turns shared by onboarding and the live coach.
struct CoachTurnView: View {
    let message: CoachMessage
    var reservesReactionSpace = false
    /// Onboarding only. The live coach already streams its text in token by token, and
    /// revealing words on top of that would animate the same arrival twice.
    var revealsWords = false
    /// What tapping this turn does, when it is still yours to change.
    ///
    /// Deliberately carried down to the bubble rather than applied to the whole turn by
    /// whoever builds it. A turn's row spans the screen, so a button wrapped around it
    /// makes the empty gutter beside an answer tappable too, and that gutter sits
    /// directly above the next question's choices. A tester spent ten minutes unable to
    /// get past the injuries screen: every near miss above the top row of buttons landed
    /// in the gutter and silently rewound onboarding a question, so the app looked like
    /// it was refusing to accept an answer.
    var onTap: (() -> Void)? = nil
    private var outgoing: Bool { message.role == .user }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var spokenLabel: String {
        let speaker = outgoing ? "You" : "Jett"
        let reaction = message.reaction.map { ". Jett reacted with \($0.rawValue)" } ?? ""
        return "\(speaker): \(message.text)" + reaction
    }

    /// One turn, but not always one bubble.
    ///
    /// Jett separates beats with a blank line and each one becomes its own message, the
    /// way somebody answering on their phone sends "Yes, but lighter." and then, a
    /// moment later, what to do about it. A chart stands on its own between them rather
    /// than inside a bubble, because it is a thing shown, not a thing said.
    var body: some View {
        VStack(alignment: outgoing ? .trailing : .leading, spacing: 5) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Group {
                    switch part {
                    case .text(let text):
                        row { tappable { bubble(text, isFirst: index == 0) } }
                    case .chart(let kind):
                        row { CoachChartCard(kind: kind) }
                    }
                }
                .transition(.arriving(from: outgoing ? .bottomTrailing : .bottomLeading))
            }
        }
        .frame(maxWidth: .infinity, alignment: outgoing ? .trailing : .leading)
        // Keyed on how many messages there are, not on the text. A bubble still filling
        // with words must not replay its arrival on every token.
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.78),
                   value: parts.count)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spokenLabel)
    }

    /// The user's own words are never split: they wrote one message, so it stays one.
    private var parts: [CoachSegment] {
        outgoing ? [.text(message.text)] : CoachSegments.parse(message.text)
    }

    @ViewBuilder
    private func tappable<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if let onTap {
            Button(action: onTap) { content() }.buttonStyle(.plain)
        } else {
            content()
        }
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            if outgoing { Spacer(minLength: 44) }
            content().layoutPriority(1)
            if !outgoing { Spacer(minLength: 36) }
        }
    }

    private func bubble(_ text: String, isFirst: Bool) -> some View {
        Group {
            if outgoing {
                Text(text).font(.body).foregroundStyle(Tokens.messageOnOutgoing)
            } else if revealsWords {
                RevealingText(text: text).font(.body)
            } else {
                Text(text).font(.body).foregroundStyle(Tokens.textPrimary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 15)
        .padding(.vertical, 11)
        .background(outgoing ? Tokens.messageOutgoing : Tokens.messageIncoming, in: bubbleShape)
        // The badge belongs to the turn, so it hangs off the first bubble in it.
        .overlay(alignment: .topLeading) { if isFirst { reactionBadge } }
        .padding(.top, isFirst && (message.reaction != nil || reservesReactionSpace) ? 12 : 0)
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 20,
                               bottomLeadingRadius: outgoing ? 20 : 6,
                               bottomTrailingRadius: outgoing ? 6 : 20,
                               topTrailingRadius: 20)
    }

    @ViewBuilder private var reactionBadge: some View {
        if let reaction = message.reaction {
            CoachReactionView(reaction: reaction)
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Tokens.messageIncoming, in: Capsule())
                .overlay(Capsule().strokeBorder(Tokens.messageCanvas, lineWidth: 2))
                .offset(x: -14, y: -16)
                .accessibilityHidden(true)
                .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
        }
    }
}

extension AnyTransition {
    /// How a message lands: up from under the one before it, growing from its own
    /// corner rather than the middle, so it reads as being sent rather than drawn.
    ///
    /// The scale is small on purpose. Anything springier is a cartoon, and this happens
    /// two or three times per answer.
    static func arriving(from corner: UnitPoint) -> AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.88, anchor: corner)
                .combined(with: .opacity)
                .combined(with: .offset(y: 6)),
            removal: .opacity)
    }
}

/// Standard Tapbacks use Apple's symbols; workout reactions keep their personality.
private struct CoachReactionView: View {
    let reaction: CoachReaction

    var body: some View {
        Group {
            switch reaction {
            case .heart:
                Image(systemName: "heart.fill").foregroundStyle(.pink)
            case .like:
                Image(systemName: "hand.thumbsup.fill").foregroundStyle(Tokens.messageOutgoing)
            case .muscle:
                Text("💪")
            case .running:
                Text("🏃")
            }
        }
    }
}

/// A familiar contact header, shared across onboarding and the live conversation.
struct CoachContactHeader: View {
    var onBack: (() -> Void)? = nil
    var isThinking = false
    var isSpeaking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack {
            Group {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left").font(.title3.weight(.medium))
                            .frame(width: 44, height: 44)
                    }
                    .tint(Tokens.messageOutgoing)
                    .accessibilityLabel("Back to your day")
                } else { Color.clear.frame(width: 44, height: 44) }
            }
            Spacer(minLength: 0)
            VStack(spacing: 4) {
                if reduceMotion { JettFace(size: 42) }
                else { JettRive(size: 42, isThinking: isThinking, isSpeaking: isSpeaking) }
                Text("Jett").font(typeSize.isAccessibilitySize ? .body : .caption)
                    .foregroundStyle(Tokens.textPrimary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Jett, your health and training coach")
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(Tokens.messageCanvas)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct ThinkingPill: View {
    var label = "Thinking"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        Text(label)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Tokens.textTertiary)
            .overlay { if !reduceMotion { sweep } }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
            .accessibilityLabel(label == "Thinking" ? "Jett is thinking" : label)
    }

    /// A band of light travelling across the word, masked to the glyphs themselves.
    private var sweep: some View {
        GeometryReader { geometry in
            LinearGradient(
                colors: [.clear, Tokens.textPrimary.opacity(0.85), .clear],
                startPoint: .leading, endPoint: .trailing)
                .frame(width: max(40, geometry.size.width * 0.55))
                .offset(x: phase * geometry.size.width)
        }
        .mask(
            Text(label)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
        )
        .allowsHitTesting(false)
    }
}

/// A step Jett took, shown the way a tool call should be: one line, past tense once it
/// has happened, and no drama. It says what was done, not how the machinery works.
struct CoachStepRow: View {
    let label: String
    var isRunning = false

    var body: some View {
        HStack(spacing: 9) {
            Group {
                if isRunning {
                    ProgressView().controlSize(.mini).tint(Tokens.textTertiary)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Tokens.accent)
                }
            }
            .frame(width: 14, height: 14)

            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Tokens.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.primary.opacity(0.04),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

/// A chart Jett asked for, drawn from history already on the device.
///
/// Nothing about this crossed the wire. The model named a metric in six tokens; every
/// number here was already in the app. That makes a chart *cheaper* than the sentence
/// it replaces, not more expensive: describing a two-week trend in prose costs three
/// or four times as many tokens as pointing at it.
struct CoachChartCard: View {
    let kind: MetricKind
    /// Set when several charts stack in one answer, where three full-height cards
    /// would push the point off the screen.
    var compact = false

    @Environment(AppModel.self) private var model

    /// The same series the app draws for this metric anywhere else, which for the balance
    /// is the only place it exists: a per-day accessor cannot answer for a running total.
    private var values: [Double] { model.chartValues(kind) }

    private var reading: MetricReading? {
        model.day?.readings.first { $0.kind == kind }
    }

    var body: some View {
        if values.count >= 2 {
            VStack(alignment: .leading, spacing: 6) {
                DrawingLine(values: values, tint: tint, lineHeight: 40) { head in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(kind.displayName)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Tokens.textTertiary)
                        InfoButton(kind)
                            .padding(.horizontal, -9)
                            .padding(.vertical, -9)
                        Spacer(minLength: 8)
                        Text(head, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Tokens.textPrimary)
                        Text(kind.unit)
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.textTertiary)
                    }
                }

                // A line on its own is a shape. This is the sentence that makes it a
                // reason, and it is read off the data rather than written by the model.
                if let reading {
                    // The window is twenty-eight calendar days however many of them
                    // recorded, so the sentence counts days rather than points.
                    Text(MetricNarration.brief(reading: reading, series: values,
                                               spanDays: AppModel.chartDays))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tokens.textTertiary)
                }
            }
            // No card around it. The answer is a single column of thought, and a
            // bordered box in the middle of it reads as an interruption rather than as
            // the evidence for the sentence above.
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(kind.displayName) over the last \(values.count) days")
        }
    }

    private var tint: Color {
        guard let reading else { return Tokens.textTertiary }
        return reading.isFavourable ? Tokens.recoveryHigh : Tokens.strainLow
    }
}

/// Shared by the first conversation and the ongoing coach. Only the send action differs.
struct CoachComposer: View {
    @Binding var draft: String
    let isStreaming: Bool
    let onSend: (String) -> Void
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !isStreaming && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("Ask about your health or training", text: $draft,
                      prompt: Text("Ask about your health or training").foregroundStyle(Tokens.textTertiary),
                      axis: .vertical)
                .font(.body)
                .lineLimit(1...4)
                .fixedSize(horizontal: false, vertical: true)
                .textFieldStyle(.plain)
                .focused($focused)
                .disabled(isStreaming)
                .padding(.leading, 18)
                .padding(.vertical, 14)
                .accessibilityLabel("Message Jett")
            Button {
                let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                guard canSend else { return }
                // After the guard, so a tap on a disabled arrow stays silent rather
                // than feeling like it worked.
                Haptics.light()
                draft = ""
                focused = false
                onSend(text)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(canSend ? Tokens.messageOnOutgoing : Tokens.textTertiary)
                    .frame(width: 36, height: 36)
                    .background(canSend ? Tokens.messageOutgoing : Tokens.surfaceSunken, in: Circle())
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!canSend)
            .padding(.trailing, 4)
            .padding(.bottom, 4)
            .accessibilityLabel("Send")
        }
        .background(Tokens.messageCanvas, in: RoundedRectangle(cornerRadius: 26))
        .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Tokens.hairline, lineWidth: 1))
        .padding(.horizontal, 16)
        // On top of the safe area, not instead of it. Six rather than ten so the field
        // lands about where the floating tab bar does on every other screen, and so it
        // does not sit against the keyboard when the safe area collapses into it.
        .padding(.bottom, 6)
        .padding(.top, 8)
    }
}


struct CoachSharingSheet: View {
    let onAllow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Tokens.messageOutgoing)
                        .accessibilityHidden(true)
                    Text("Chat with Jett").font(.title2.bold())
                    // "We send your biological sex" read as a statement about data the
                    // app holds, and a tester who had skipped that optional question
                    // said so: either the sheet was lying or it was collecting a blank.
                    // It was neither. The list is what can go, and each line only goes
                    // when there is something in it, which the sheet now says once
                    // rather than hedging every item.
                    Text("Jett's replies are written by an AI model. With your permission, we send whichever of these you have given the app:")
                    Label("Your messages, goals, physical limits, training experience, equipment, check-ins, and training plan", systemImage: "bubble.left")
                    Label("Age, height, biological sex, and summaries of sleep, heart metrics, activity, workouts, body measurements, and logged nutrition", systemImage: "heart.text.clipboard")
                    Text("Anything you skipped or never recorded is not sent, and Jett is not told a guess in its place.")
                        .font(.subheadline).foregroundStyle(Tokens.textTertiary)
                    Text("This goes to Coach Jett's server, which passes it to the AI provider that writes the reply. Your birthday and raw Health records stay on your phone. Turn sharing off anytime in Profile.")
                        .font(.subheadline).foregroundStyle(Tokens.textTertiary)
                }
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button("Allow and continue", action: onAllow)
                        .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                        .controlSize(.large).frame(maxWidth: .infinity)
                    Button("Not now", action: onCancel).frame(minHeight: 44)
                }
                .tint(Tokens.messageOutgoing)
                .padding(.horizontal, 24).padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Tokens.messageCanvas)
            }
            .background(Tokens.messageCanvas)
        }
        .presentationDragIndicator(.visible)
    }
}

extension View {
    @ViewBuilder func conversationScrollAnchor() -> some View {
        if #available(iOS 18.0, *) {
            self.defaultScrollAnchor(.bottom, for: .sizeChanges)
        } else {
            self
        }
    }
}
