import SwiftUI

/// How an answer arrives.
///
/// The assistant's text is not a bubble. A bubble is for a thing somebody said to you;
/// a coach's answer is the content of the screen, so it runs full width in plain prose
/// and only the user's own message gets a container. That single choice is most of what
/// separates a chat toy from a tool.
struct CoachTurnView: View {
    let message: CoachMessage

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 44)
                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundStyle(Tokens.onAccent)
                    .padding(.vertical, 10).padding(.horizontal, 14)
                    .background(Tokens.accent,
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You: \(message.text)")

        case .assistant:
            // The first line is the answer and is set as one: bigger, heavier, and on
            // its own. Everything after it is the detail you read only if you want it.
            let segments = CoachSegments.parse(message.text)
            VStack(alignment: .leading, spacing: 15) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    switch segment {
                    case .text(let prose):
                        prosePart(prose, isFirst: index == 0)
                    case .chart(let kind):
                        CoachChartCard(kind: kind)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Jett: \(message.text)")
        }
    }

    /// The opening run of prose carries the answer, so its first sentence is set as a
    /// headline. Everything after it is detail.
    @ViewBuilder
    private func prosePart(_ prose: String, isFirst: Bool) -> some View {
        let answer = isFirst ? CoachAnswer.split(prose) : (lead: "", body: prose)
        VStack(alignment: .leading, spacing: 9) {
            if !answer.lead.isEmpty {
                Text(Self.formatted(answer.lead))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !answer.body.isEmpty {
                Text(Self.formatted(answer.body))
                    .font(.system(size: 15))
                    .foregroundStyle(Tokens.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Inline markdown only, and whitespace preserved.
    ///
    /// Block syntax is deliberately not interpreted: half-written text arrives on every
    /// keystroke of the stream, and a block parser reflows the whole answer each time a
    /// character lands — the paragraph jumps around while you are reading it.
    static func formatted(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// One quiet word while there is nothing to show yet.
///
/// Not a spinner and not an empty bubble: a container with nothing in it reads as a
/// failure. This holds no layout it will not fill, and gives way the moment the first
/// token lands.
struct ThinkingPill: View {
    var label = "Thinking"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        Text(label)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Tokens.textSecondary.opacity(0.55))
            .overlay { if !reduceMotion { sweep } }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
            .accessibilityLabel("Jett is thinking")
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
                .font(.system(size: 15, weight: .medium))
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
                    ProgressView().controlSize(.mini).tint(Tokens.textSecondary)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Tokens.accent)
                }
            }
            .frame(width: 14, height: 14)

            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Tokens.textSecondary)
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
/// it replaces, not more expensive — describing a two-week trend in prose costs three
/// or four times as many tokens as pointing at it.
struct CoachChartCard: View {
    let kind: MetricKind
    /// Set when several charts stack in one answer, where three full-height cards
    /// would push the point off the screen.
    var compact = false

    @Environment(AppModel.self) private var model

    private var values: [Double] {
        model.series.suffix(28).compactMap { $0.value(for: kind) }
    }

    private var reading: MetricReading? {
        model.day?.readings.first { $0.kind == kind }
    }

    var body: some View {
        if values.count >= 2 {
            VStack(alignment: .leading, spacing: 6) {
                DrawingLine(values: values, tint: tint, lineHeight: 40) { head in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(kind.displayName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Tokens.textSecondary)
                        InfoButton(kind)
                            .padding(.horizontal, -9)
                            .padding(.vertical, -9)
                        Spacer(minLength: 8)
                        Text(head, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Tokens.textPrimary)
                        Text(kind.unit)
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.textSecondary)
                    }
                }

                // A line on its own is a shape. This is the sentence that makes it a
                // reason, and it is read off the data rather than written by the model.
                if let reading {
                    Text(MetricNarration.brief(reading: reading, series: values))
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
        guard let reading else { return Tokens.textSecondary }
        return reading.isFavourable ? Tokens.recoveryHigh : Tokens.strainLow
    }
}
