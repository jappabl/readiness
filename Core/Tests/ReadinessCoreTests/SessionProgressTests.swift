import Testing
@testable import ReadinessCore

/// Coming back to a session you walked away from.
///
/// A tester logged three sets of leg press, moved to the next exercise, closed the
/// workout and reopened it. It put him back on leg press asking for a fourth set, past
/// the three that were planned, because the screen always started at the first exercise.
@Suite("Reopening a session")
struct SessionProgressTests {

    @Test func afreshSessionStartsAtTheTop() {
        #expect(SessionProgress.resumeIndex(planned: [3, 3, 3], logged: [0, 0, 0]) == 0)
    }

    @Test func afinishedExerciseIsNotOfferedAgain() {
        #expect(SessionProgress.resumeIndex(planned: [3, 3, 3], logged: [3, 0, 0]) == 1)
        #expect(SessionProgress.resumeIndex(planned: [3, 3, 3], logged: [3, 3, 0]) == 2)
    }

    /// Extra sets are allowed, so being over the plan still counts as done.
    @Test func goingPastThePlanStillCountsAsFinished() {
        #expect(SessionProgress.resumeIndex(planned: [3, 3], logged: [5, 0]) == 1)
    }

    /// Somebody who skipped one and carried on is owed the one they skipped.
    @Test func askippedExerciseIsWhereYouComeBackTo() {
        #expect(SessionProgress.resumeIndex(planned: [3, 3, 3], logged: [3, 0, 3]) == 1)
    }

    /// A session with everything done opens at its end, not its beginning.
    @Test func afinishedSessionOpensAtTheEnd() {
        #expect(SessionProgress.resumeIndex(planned: [3, 3, 3], logged: [3, 3, 3]) == 2)
    }

    @Test func anEmptyTemplateDoesNotCrash() {
        #expect(SessionProgress.resumeIndex(planned: [], logged: []) == 0)
        #expect(SessionProgress.resumeIndex(planned: [3, 3], logged: []) == 0)
    }
}
