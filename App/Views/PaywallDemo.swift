import SwiftUI

/// Jett, running, on the paywall.
///
/// A list of features is a claim. This is the thing itself: the question appears, the
/// word shimmers, the answer lands a few words at a time, and the chart draws itself
/// from *this user's own history*. Nobody reads three bullet points about a coach; they
/// will watch one work for eight seconds.
///
/// The script never states a measurement. The chart carries the specifics, and it is
/// real, so the demo cannot claim something the data does not say.
struct PaywallDemo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var question = ""
    @State private var thinking = false
    @State private var answer = ""
    @State private var showsChart = false
    @State private var showsClose = false

    private static let ask = "Can I still train legs today?"
    private static let opening = "Yes, but lighter today."
    private static let closing = "Take 15% off the bar and stop at 4 RIR. You'll still get the work in."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !question.isEmpty {
                HStack {
                    Spacer(minLength: 40)
                    Text(question)
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.onAccent)
                        .padding(.vertical, 9).padding(.horizontal, 13)
                        .background(Tokens.accent, in: RoundedRectangle(cornerRadius: 16,
                                                                        style: .continuous))
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            if thinking { ThinkingPill() }

            if !answer.isEmpty {
                Text(answer)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsChart {
                CoachChartCard(kind: .hrv)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }

            if showsClose {
                Text(Self.closing)
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 250, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: question)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: thinking)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: showsChart)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: showsClose)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A demonstration of Coach Jett answering a question.")
        .task { await play() }
    }

    /// Loops for as long as the paywall is on screen. Reduce Motion gets the finished
    /// state immediately rather than a performance.
    private func play() async {
        guard !reduceMotion else {
            question = Self.ask
            answer = Self.opening
            showsChart = true
            showsClose = true
            return
        }
        while !Task.isCancelled {
            reset()
            try? await Task.sleep(for: .milliseconds(700))
            question = Self.ask

            try? await Task.sleep(for: .milliseconds(650))
            thinking = true
            try? await Task.sleep(for: .milliseconds(1400))
            thinking = false

            for word in Self.opening.split(separator: " ") {
                answer += (answer.isEmpty ? "" : " ") + word
                try? await Task.sleep(for: .milliseconds(70))
            }

            try? await Task.sleep(for: .milliseconds(350))
            showsChart = true
            try? await Task.sleep(for: .milliseconds(900))
            showsClose = true

            try? await Task.sleep(for: .seconds(4))
        }
    }

    private func reset() {
        question = ""
        thinking = false
        answer = ""
        showsChart = false
        showsClose = false
    }
}
