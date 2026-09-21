import Testing
@testable import ReadinessCore

/// The sentence Jett opens the day with.
///
/// It said "Ahead of baseline. Train as planned." Hao read that on his own screen and
/// said it says nothing, and he is right: baseline is a word this app invented for its
/// own arithmetic, and the two numbers it is summarising are sitting six inches above
/// it. Name them.
@Suite("The morning greeting")
struct MorningGreetingTests {

    private func score(_ kind: SignalKind, _ value: Double?) -> SignalScore {
        SignalScore(kind: kind, value: value,
                    band: value.map { kind == .sleep ? .sleep(percent: $0)
                                                     : .recovery(percent: $0) },
                    contributors: [], coverage: value == nil ? .unavailable : .full,
                    modelVersion: "test")
    }

    @Test("two good numbers read as one thing, not two")
    func bothGood() {
        let line = MorningGreeting.signals(recovery: score(.recovery, 78),
                                           sleep: score(.sleep, 92))
        #expect(line == "Sleep and recovery both look good.")
    }

    @Test("two that disagree are both named")
    func mixed() {
        let line = MorningGreeting.signals(recovery: score(.recovery, 12),
                                           sleep: score(.sleep, 92))
        #expect(line == "Sleep looks good, recovery low.")
    }

    @Test("a bad morning says so in the same shape")
    func bothLow() {
        let line = MorningGreeting.signals(recovery: score(.recovery, 10),
                                           sleep: score(.sleep, 40))
        #expect(line == "Sleep and recovery both look low.")
    }

    /// A phone with no wearable has no recovery, every morning, for ever. The sentence
    /// has to work without it rather than naming a number that is not there.
    @Test("a missing signal is left out rather than guessed at")
    func oneMissing() {
        #expect(MorningGreeting.signals(recovery: score(.recovery, nil),
                                        sleep: score(.sleep, 88)) == "Sleep looks good.")
        #expect(MorningGreeting.signals(recovery: score(.recovery, 70),
                                        sleep: score(.sleep, nil)) == "Recovery looks good.")
    }

    @Test("with nothing measured there is nothing to describe")
    func bothMissing() {
        #expect(MorningGreeting.signals(recovery: score(.recovery, nil),
                                        sleep: score(.sleep, nil)) == nil)
    }

    /// The instruction is the part that survives whatever the numbers did, so it is
    /// never dropped, and it is never left dangling behind a full stop that is missing.
    @Test("the instruction always arrives")
    func instructionSurvives() {
        let full = MorningGreeting.sentence(recovery: score(.recovery, 78),
                                            sleep: score(.sleep, 92),
                                            instruction: "Train as planned.")
        #expect(full == "Sleep and recovery both look good. Train as planned.")

        let bare = MorningGreeting.sentence(recovery: score(.recovery, nil),
                                            sleep: score(.sleep, nil),
                                            instruction: "Train as planned.")
        #expect(bare == "Train as planned.")
    }

    /// The word comes off the band, so the ring's colour and the sentence cannot
    /// disagree. They were two readings of the same number before this existed.
    @Test("the word matches the colour the ring is drawing",
          arguments: [(90.0, "good"), (40.0, "normal"), (5.0, "low")])
    func wordFollowsBand(percent: Double, expected: String) {
        let line = MorningGreeting.signals(recovery: score(.recovery, percent),
                                           sleep: score(.sleep, nil))
        #expect(line == "Recovery looks \(expected).")
    }
}
