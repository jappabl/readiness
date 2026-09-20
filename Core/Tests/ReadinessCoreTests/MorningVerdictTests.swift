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
        #expect(sentence?.contains(sleepScore.summary) == true)
        #expect(sentence?.contains(recoveryScore.summary) != true)
    }

    @Test("the sentence comes from whichever signal moved further, even when recovery is worse")
    func worseRecoveryWins() {
        // Mirrors worseSignalWins with the roles swapped: recovery is the more negative
        // of two qualifying signals. A worstNews that always favored one parameter
        // regardless of which one actually moved further would pass every other test in
        // this file — none of them has recovery as the worse of two candidates that both
        // clear the interruption threshold — and only be caught here.
        let recoveryScore = score(.recovery, value: 30, magnitude: -14, title: "Heart rate variability")
        let sleepScore = score(.sleep, value: 55, magnitude: -6, title: "Deep sleep")
        let sentence = MorningVerdict.sentence(
            recovery: recoveryScore, sleep: sleepScore, recentSleepScores: ordinaryHistory)
        #expect(sentence?.contains(recoveryScore.summary) == true)
        #expect(sentence?.contains(sleepScore.summary) != true)
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
        #expect(sentence == "✨ Your best night in three weeks.")
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
        #expect(sentence == "✨ Your best night in two weeks.")
    }

    @Test("a best only has to beat the last three weeks, not all of history")
    func bestIgnoresHistoryOlderThanTheWindow() {
        // 40 nights: the oldest 19 are a 99 no recent night can beat, the most recent 21
        // are 94s that tonight's 96 does beat. Every other fixture in this file is
        // bestWindow (21) or fewer, so `.suffix(bestWindow)` never actually trims
        // anything in them — deleting it, or swapping it for `.prefix`, changes none of
        // their outcomes. This is the one history long enough to tell the difference.
        let longHistory = Array(repeating: 99.0, count: 19) + Array(repeating: 94.0, count: 21)
        let sentence = MorningVerdict.sentence(
            recovery: score(.recovery, value: 82, magnitude: 8),
            sleep: score(.sleep, value: 96, magnitude: 6),
            recentSleepScores: longHistory)
        #expect(sentence == "✨ Your best night in three weeks.")
    }

    @Test("a score the app does not have says nothing")
    func unavailableIsSilent() {
        let missing = SignalScore(kind: .sleep, value: nil, band: nil, contributors: [],
                                  coverage: .unavailable, modelVersion: "test")
        #expect(MorningVerdict.sentence(
            recovery: missing, sleep: missing,
            recentSleepScores: ordinaryHistory) == nil)
    }

    // Added in review: `worstNews` filtered only `.unavailable`, so a `.buildingBaseline`
    // score with a -9 contributor produced a confident interruption off a number the
    // app's own UI labels "Still learning your normal" (InsightsView.coverageTitle) — a
    // caveat a lock screen cannot carry.
    @Test("a still-learning score does not interrupt, even with a big enough contributor")
    func buildingBaselineCoverageIsSilent() {
        #expect(MorningVerdict.sentence(
            recovery: score(.recovery, value: 44, magnitude: -9, coverage: .buildingBaseline),
            sleep: flatScore(.sleep, value: 80),
            recentSleepScores: ordinaryHistory) == nil)
    }

    // Added in review: `bestNight` uses `value > best`, but nothing exercised the
    // boundary itself, so a regression to `value >= best` — congratulating a tied night
    // as a new record — turned nothing red. The file's own doc comment calls the lock
    // screen "the one place the app cannot afford small lies."
    @Test("tying the record, not beating it, stays quiet")
    func tyingTheBestIsSilent() {
        #expect(MorningVerdict.sentence(
            recovery: flatScore(.recovery, value: 72),
            sleep: flatScore(.sleep, value: 94),
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
