import Foundation
import Testing
@testable import ReadinessCore

/// Telling "missing today" apart from "your phone cannot measure this".
///
/// A phone-only sleeper is the commonest first-run profile there is, and every morning
/// the app listed four reasons it could not score them properly, none of which waiting
/// would ever satisfy. The answer given in onboarding is a starting point; the record
/// corrects it from there.
///
/// See docs/superpowers/specs/2026-09-20-absent-streams-design.md.
@Suite("Whether there is a watch")
struct WatchPresenceTests {

    /// Nights newest first, as the app holds them.
    private func nights(staged: Int, then empty: Int) -> [Bool] {
        Array(repeating: true, count: staged) + Array(repeating: false, count: empty)
    }

    @Test("said yes and the stages arrive: nothing to work out")
    func saidYesAndWearsIt() {
        #expect(WatchPresence.hasWatch(saidYes: true, nightsWithStages: nights(staged: 20, then: 0)))
    }

    @Test("said no and nothing ever arrives: no watch")
    func saidNoAndNoneArrives() {
        #expect(!WatchPresence.hasWatch(saidYes: false,
                                        nightsWithStages: nights(staged: 0, then: 40)))
    }

    @Test("a fortnight away does not turn an owner into a phone-only sleeper")
    func aHolidayIsNotAReclassification() {
        // The asymmetry exists for this: silence the nudge that their watch is off and
        // the app stops being able to tell them the one thing it noticed.
        let afterTwoWeeksOff = nights(staged: 0, then: 14) + nights(staged: 30, then: 0)
        #expect(WatchPresence.hasWatch(saidYes: true, nightsWithStages: afterTwoWeeksOff))
    }

    @Test("four weeks of nothing is an answer, whatever they said")
    func longSilenceOverridesTheAnswer() {
        let quiet = nights(staged: 0, then: WatchPresence.daysToConcludeAbsent)
        #expect(!WatchPresence.hasWatch(saidYes: true, nightsWithStages: quiet))
    }

    @Test("a week of stages is a watch, whatever they said")
    func stagesOverrideTheAnswerQuickly() {
        // Out fast, in slow. Somebody who just bought one should not wait a month to be
        // recognised, and the congratulation should not lag behind the purchase.
        let justBought = nights(staged: WatchPresence.daysToConcludePresent, then: 60)
        #expect(WatchPresence.hasWatch(saidYes: false, nightsWithStages: justBought))
    }

    @Test("with no answer and no record, assume nothing is being worn")
    func unknownStartsQuiet() {
        // Being wrong this way lists nothing. Being wrong the other way lists four
        // things that will never arrive, every morning.
        #expect(!WatchPresence.hasWatch(saidYes: nil, nightsWithStages: []))
    }

    @Test("with no answer, the data decides on its own")
    func unknownFollowsTheData() {
        #expect(WatchPresence.hasWatch(saidYes: nil, nightsWithStages: nights(staged: 10, then: 0)))
    }
}

@Suite("When to say something about the watch")
struct WatchNudgeTests {

    private func nights(staged: Int, then empty: Int) -> [Bool] {
        Array(repeating: true, count: staged) + Array(repeating: false, count: empty)
    }

    @Test("said yes, and it has not been worn for a week")
    func notWorn() {
        #expect(WatchPresence.nudge(saidYes: true, nightsWithStages: nights(staged: 0, then: 7))
                == .notWearingIt)
    }

    @Test("six nights is not yet worth interrupting for")
    func notYet() {
        #expect(WatchPresence.nudge(saidYes: true, nightsWithStages: nights(staged: 0, then: 6))
                == nil)
    }

    @Test("said no, and stages started arriving")
    func gotOne() {
        #expect(WatchPresence.nudge(saidYes: false, nightsWithStages: nights(staged: 7, then: 30))
                == .gotOne)
    }

    @Test("one night of stages could be a borrowed watch")
    func oneNightIsNotAPurchase() {
        #expect(WatchPresence.nudge(saidYes: false, nightsWithStages: nights(staged: 1, then: 30))
                == nil)
    }

    @Test("nothing to say when the answer and the data agree")
    func silenceWhenTheyAgree() {
        #expect(WatchPresence.nudge(saidYes: true, nightsWithStages: nights(staged: 9, then: 0)) == nil)
        #expect(WatchPresence.nudge(saidYes: false, nightsWithStages: nights(staged: 0, then: 40)) == nil)
    }

    @Test("nothing to say to somebody who was never asked")
    func silenceWithoutAnAnswer() {
        #expect(WatchPresence.nudge(saidYes: nil, nightsWithStages: nights(staged: 0, then: 40)) == nil)
        #expect(WatchPresence.nudge(saidYes: nil, nightsWithStages: nights(staged: 9, then: 0)) == nil)
    }
}

/// What the recovery screen says when it has no number to show.
///
/// "Still building your baseline" is true of somebody a week into owning a watch and a
/// lie to somebody who owns none: the baseline is not being built. A tester answered no
/// to the watch question, saw a dash, and could not tell whether the app was broken.
@Suite("Recovery with nothing to show")
struct RecoveryNoteTests {

    @Test func areadingNeedsNoExcuse() {
        #expect(WatchPresence.recoveryNote(hasReading: true, hasWatch: true) == nil)
        #expect(WatchPresence.recoveryNote(hasReading: true, hasWatch: false) == nil)
    }

    @Test func awatchWithNoHistoryYetIsStillBuilding() {
        #expect(WatchPresence.recoveryNote(hasReading: false, hasWatch: true)
                == "Still building your baseline.")
    }

    /// The whole point: do not promise a number that is not coming.
    @Test func noWatchIsToldSoRatherThanLeftWaiting() throws {
        let note = try #require(WatchPresence.recoveryNote(hasReading: false, hasWatch: false))
        #expect(note.contains("needs a watch"))
        #expect(!note.contains("building"))
        // And it says what does still work, so the answer is not only bad news.
        #expect(note.contains("Sleep and strain"))
    }
}
