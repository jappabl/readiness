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

    private static let answer = """
        You're **under baseline** today, mostly on HRV — 14.2 ms against your 53.4 ms \
        baseline, which is the lowest it has been in two weeks. Resting heart rate is up \
        to 70 bpm as well, and the two moving together usually means you are still \
        carrying Tuesday's session.

        I'd take 15% off the bar and stop every set at 4 reps in reserve. That keeps the \
        movement and the practice without adding to what you are already recovering from.

        What this cannot see is whether you slept badly because of training or because of \
        something else entirely — if it was a late night rather than fatigue, this reads \
        harsher than it should.
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
