#if DEBUG
import Foundation

/// Streams a canned answer so the coach's UI can be built and inspected without a key
/// and without spending anything.
///
/// It exists because the parts most likely to be wrong — the thinking state, how text
/// lands as it arrives, where a tool step appears — are invisible in source and can
/// only be judged by watching them. Paying a model per render to find that out is a bad
/// trade, and doing it without a key is impossible.
struct RehearsalCoachProvider: CoachProvider {
    var isConfigured: Bool { true }

    /// Roughly the cadence of a real stream, so the pacing being judged is the real one.
    private let firstTokenDelay = Duration.milliseconds(900)
    private let perChunk = Duration.milliseconds(45)

    /// Deliberately states no measurement. The chart below it is drawn from real
    /// history, and a canned line claiming "lowest in two weeks" sits directly above a
    /// chart that may say otherwise. Same rule as the paywall demo.
    private static let answer = """
        You're flat today. Here's what moved.

        [chart:hrv]

        Take 15% off the bar and stop at 4 RIR. You'll still get the work in.
        """

    func stream(messages: [CoachMessage],
                context: CoachContext,
                applyTool: @escaping @Sendable (CoachToolCall) async -> String)
        -> AsyncThrowingStream<CoachEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(for: firstTokenDelay)

                let asksForChange = messages.last?.text.localizedCaseInsensitiveContains("easier") == true
                    || messages.last?.text.localizedCaseInsensitiveContains("legs") == true

                if asksForChange {
                    let call = CoachToolCall(
                        id: "rehearsal",
                        adjustment: .reduceLoad(percent: 15),
                        reason: "HRV is 2.5 SD below your baseline and resting heart rate is up.")
                    continuation.yield(.toolCall(call))
                    _ = await applyTool(call)
                    try? await Task.sleep(for: .milliseconds(400))
                }

                // Word by word, the way a real stream arrives — never the whole answer
                // at once, which is what makes a fake look fake.
                for word in Self.answer.split(separator: " ", omittingEmptySubsequences: false) {
                    continuation.yield(.text(word + " "))
                    try? await Task.sleep(for: perChunk)
                }
                continuation.finish()
            }
        }
    }
}
#endif
