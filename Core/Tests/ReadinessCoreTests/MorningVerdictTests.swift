import Testing
import Foundation
@testable import ReadinessCore

/// The morning verdict is the app's core output. It is not budgeted, and it is not
/// suppressed for repeating itself — a fifth consecutive rough night is a fifth day the
/// user should train differently.
@Suite("The morning verdict")
struct MorningVerdictTests {

    /// A score with one contributor that moved it by `magnitude` points.
    ///
    /// `title` defaults to the same contributor every other test in this file uses.
    /// `worseSignalWins` overrides it, because two scores with an identical lead
    /// contributor produce an identical `summary` regardless of which one is picked —
    /// that would let the wrong signal win the sentence without the test noticing.
    private func score(_ kind: SignalKind, value: Double, magnitude: Double,
                       coverage: ScoreCoverage = .full,
                       title: String = "Heart rate variability") -> SignalScore {
        SignalScore(
            kind: kind, value: value, band: nil,
            contributors: [ScoreContributor(
                id: "hrv", title: title, value: 42, unit: "ms",
                comparison: 58, comparisonLabel: "your normal", state: .payAttention,
                magnitude: magnitude, explanation: "")],
            coverage: coverage, neutral: 50, modelVersion: "test")
    }

    private func flatScore(_ kind: SignalKind, value: Double) -> SignalScore {
        score(kind, value: value, magnitude: 0.4)
    }

    /// Above every "ordinary" fixture below (80, 88) and below the 96 the exceptional
    /// tests use. A history beneath the ordinary values would make every silent morning
    /// a personal best.
    private let ordinaryHistory = Array(repeating: 94.0, count: 21)

    @Test("a night that pulled the score well down speaks")
    func badNightSpeaks() {
        let sentence = MorningVerdict.sentence(
            recovery: score(.recovery, value: 44, magnitude: -9),
            sleep: flatScore(.sleep, value: 80),
            recentSleepScores: ordinaryHistory)
        #expect(sentence != nil)
    }

    @Test("a night nothing stood out in stays quiet")
    func unremarkableNightIsSilent() {
        #expect(MorningVerdict.sentence(
            recovery: flatScore(.recovery, value: 72),
            sleep: flatScore(.sleep, value: 80),
            recentSleepScores: ordinaryHistory) == nil)
    }

    @Test("worth saying on screen is not yet worth a lock screen")
    func screenBarIsNotTheInterruptionBar() {
        // 3 points clears SignalScore.notableMagnitude (2.0) and not
        // MorningVerdict.notableForInterruption (5.0).
        #expect(SignalScore.notableMagnitude < 3.0)
        #expect(MorningVerdict.notableForInterruption > 3.0)
        #expect(MorningVerdict.sentence(
            recovery: score(.recovery, value: 64, magnitude: -3),
            sleep: flatScore(.sleep, value: 80),
            recentSleepScores: ordinaryHistory) == nil)
    }

    @Test("a bad night shows up through sleep even when recovery is clean")
    func sleepCanCarryTheNews() {
        let sentence = MorningVerdict.sentence(
            recovery: flatScore(.recovery, value: 71),
            sleep: score(.sleep, value: 58, magnitude: -11),
            recentSleepScores: ordinaryHistory)
        #expect(sentence != nil)
    }

    @Test("the sentence comes from whichever signal moved further")
    func worseSignalWins() {
        // Distinct titles so the two summaries cannot coincide: if the implementation
        // ever picked the less-negative signal (recovery, -6) instead of the more
        // negative one (sleep, -14), the sentence would name the wrong contributor and
        // this assertion would catch it. With the shared "Heart rate variability"
        // fixture both scores read identically regardless of which one is chosen, and
        // the test would pass either way.
        let recoveryScore = score(.recovery, value: 55, magnitude: -6, title: "Heart rate variability")
        let sleepScore = score(.sleep, value: 40, magnitude: -14, title: "Deep sleep")
        let sentence = MorningVerdict.sentence(
            recovery: recoveryScore, sleep: sleepScore, recentSleepScores: ordinaryHistory)
        #expect(sentence == sleepScore.summary)
        #expect(sentence != recoveryScore.summary)
    }

    @Test("an ordinary good night stays quiet")
    func goodNightIsSilent() {
        #expect(MorningVerdict.sentence(
            recovery: score(.recovery, value: 82, magnitude: 8),
            sleep: score(.sleep, value: 88, magnitude: 6),
            recentSleepScores: ordinaryHistory) == nil)
    }

    @Test("a genuine three-week best speaks")
    func exceptionalNightSpeaks() {
        let sentence = MorningVerdict.sentence(
            recovery: score(.recovery, value: 82, magnitude: 8),
            sleep: score(.sleep, value: 96, magnitude: 6),
            recentSleepScores: ordinaryHistory)
        #expect(sentence == "Your best night in three weeks.")
    }

    @Test("a best is not claimed without enough nights to claim it against")
    func thinHistoryClaimsNothing() {
        #expect(MorningVerdict.sentence(
            recovery: score(.recovery, value: 82, magnitude: 8),
            sleep: score(.sleep, value: 96, magnitude: 6),
            recentSleepScores: Array(repeating: 94.0, count: 5)) == nil)
    }

    @Test("a best claims only the weeks it actually beat")
    func bestNamesTheRealWindow() {
        let sentence = MorningVerdict.sentence(
            recovery: score(.recovery, value: 82, magnitude: 8),
            sleep: score(.sleep, value: 96, magnitude: 6),
            recentSleepScores: Array(repeating: 94.0, count: 14))
        #expect(sentence == "Your best night in two weeks.")
    }

    @Test("a score the app does not have says nothing")
    func unavailableIsSilent() {
        let missing = SignalScore(kind: .sleep, value: nil, band: nil, contributors: [],
                                  coverage: .unavailable, modelVersion: "test")
        #expect(MorningVerdict.sentence(
            recovery: missing, sleep: missing,
            recentSleepScores: ordinaryHistory) == nil)
    }

    @Test("bad news outranks a best, on the morning that manages both")
    func badNewsWins() {
        let sentence = MorningVerdict.sentence(
            recovery: score(.recovery, value: 38, magnitude: -12),
            sleep: score(.sleep, value: 96, magnitude: 6),
            recentSleepScores: ordinaryHistory)
        #expect(sentence != "Your best night in three weeks.")
        #expect(sentence != nil)
    }
}
