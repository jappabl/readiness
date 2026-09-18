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
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sceneIndex = 0
    @State private var question = ""
    @State private var thinking = false
    @State private var answer = ""
    @State private var showsChart = false
    @State private var showsStep = false
    @State private var showsClose = false

    private var scene: Scene {
        let all = scenes
        return all[min(sceneIndex, all.count - 1)]
    }

    /// Three scenes, because one answer only shows one thing Jett does. Together they
    /// show him answering, pulling a trend, and changing the session, which is the
    /// whole product without a single bullet point.
    ///
    /// No scene states a measurement. The chart carries the specifics and it is real,
    /// so the demo can never claim something this user's data does not say.
    private struct Scene {
        let question: String
        let lead: String
        var charts: [MetricKind] = []
        var step: String?
        var closing: String
    }

    /// The charts are whichever metrics actually drove today's call for this user, not
    /// a hardcoded favourite. No scripted line names a metric, so the demo cannot end up
    /// asserting that sleep is the problem while the chart shows a heart rate.
    private var scenes: [Scene] {
        let drivers = model.day?.readiness.contributions
            .sorted { abs($0.points) > abs($1.points) }
            .map(\.kind) ?? []

        return [
            // Two charts, because two things moving together is the argument. One
            // metric on its own rarely is.
            Scene(question: "Can I still train legs today?",
                  lead: "Yes, but lighter.",
                  charts: Array(drivers.prefix(2)),
                  closing: "Take 15% off the bar and stop at 4 RIR. You'll still get the work in."),
            Scene(question: "Why do I feel so flat this week?",
                  lead: "Here's what moved.",
                  charts: Array(drivers.prefix(3)),
                  closing: "Everything else is sitting where it usually does."),
            Scene(question: "Make today easier.",
                  lead: "Done. Cut to three sets.",
                  step: "Adjusting today's session",
                  closing: "Same lifts, same loads, less volume. Approve it and I'll update the day."),
        ]
    }

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

            if showsStep, let label = scene.step {
                CoachStepRow(label: label)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if showsChart {
                ForEach(Array(scene.charts.enumerated()), id: \.element) { order, kind in
                    CoachChartCard(kind: kind, compact: true)
                        .id("\(sceneIndex)-\(kind.rawValue)")
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }

            if showsClose {
                Text(scene.closing)
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: question)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: thinking)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: showsChart)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: showsStep)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: showsClose)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A demonstration of Coach Jett answering a question.")
        .task { await play() }
    }

    /// Loops for as long as the paywall is on screen. Reduce Motion gets the finished
    /// state immediately rather than a performance.
    private func play() async {
        guard !reduceMotion else {
            question = scene.question
            answer = scene.lead
            showsChart = !scene.charts.isEmpty
            showsStep = scene.step != nil
            showsClose = true
            return
        }
        while !Task.isCancelled {
            for index in scenes.indices {
                reset()
                sceneIndex = index
                try? await Task.sleep(for: .milliseconds(500))
                question = scene.question

                try? await Task.sleep(for: .milliseconds(600))
                thinking = true
                try? await Task.sleep(for: .milliseconds(1300))
                thinking = false

                if scene.step != nil {
                    showsStep = true
                    try? await Task.sleep(for: .milliseconds(650))
                }

                for word in scene.lead.split(separator: " ") {
                    answer += (answer.isEmpty ? "" : " ") + word
                    try? await Task.sleep(for: .milliseconds(75))
                }

                if !scene.charts.isEmpty {
                    try? await Task.sleep(for: .milliseconds(300))
                    showsChart = true
                    try? await Task.sleep(for: .milliseconds(2000))
                }

                try? await Task.sleep(for: .milliseconds(400))
                showsClose = true
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func reset() {
        question = ""
        thinking = false
        answer = ""
        showsChart = false
        showsStep = false
        showsClose = false
    }
}
