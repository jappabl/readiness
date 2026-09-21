import SwiftUI

/// Jett, running, on the paywall.
///
/// A list of features is a claim. This is the thing itself: the question appears, the
/// word shimmers, the answer lands a few words at a time, and the chart draws itself
/// from *this user's own history*. Nobody reads three bullet points about a coach; they
/// will watch one work for eight seconds.
///
/// It is drawn by `CoachTurnView`, the same view the real conversation uses, and not by
/// a copy of it. The copy had drifted: the question sat in an accent rectangle instead
/// of the outgoing bubble, and Jett's answer had no bubble at all, so the one screen
/// asking somebody to pay for the chat was the one screen that did not look like it.
/// Sharing the view is also the only way it stays true, since the demo now inherits
/// every change to how a message is drawn.
///
/// The script never states a measurement. The chart carries the specifics, and it is
/// real, so the demo cannot claim something the data does not say.
struct PaywallDemo: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sceneIndex = 0
    @State private var question = ""
    @State private var thinking = false
    /// One growing string, the way a real reply arrives. Charts are `[chart:name]`
    /// markers inside it, parsed by the same segment reader the live stream uses, so
    /// the demo cannot render a chart the conversation would not.
    @State private var reply = ""
    @State private var showsStep = false

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
                  charts: Array(drivers.prefix(2)),
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
                CoachTurnView(message: CoachMessage(role: .user, text: question))
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            if thinking { ThinkingPill() }

            if showsStep, let label = scene.step {
                CoachStepRow(label: label)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !reply.isEmpty {
                CoachTurnView(message: CoachMessage(role: .assistant, text: reply))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: question)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: thinking)
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: showsStep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("A demonstration of Coach Jett answering a question.")
        .task { await play() }
    }

    /// The finished message, markers and all, exactly as the live stream would end up.
    private var finishedReply: String {
        var parts = [scene.lead]
        parts.append(contentsOf: scene.charts.map { "[chart:\($0.rawValue)]" })
        parts.append(scene.closing)
        return parts.joined(separator: "\n")
    }

    /// Loops for as long as the paywall is on screen. Reduce Motion gets the finished
    /// state immediately rather than a performance.
    private func play() async {
        guard !reduceMotion else {
            question = scene.question
            reply = finishedReply
            showsStep = scene.step != nil
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
                    reply += (reply.isEmpty ? "" : " ") + word
                    try? await Task.sleep(for: .milliseconds(75))
                }

                // Markers, not a flag. The bubble grows around each chart as it lands,
                // which is what the live stream does when the model writes one.
                for kind in scene.charts {
                    try? await Task.sleep(for: .milliseconds(300))
                    reply += "\n[chart:\(kind.rawValue)]"
                }
                if !scene.charts.isEmpty { try? await Task.sleep(for: .milliseconds(1700)) }

                try? await Task.sleep(for: .milliseconds(400))
                reply += "\n" + scene.closing
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func reset() {
        question = ""
        thinking = false
        reply = ""
        showsStep = false
    }
}
