import Testing
@testable import ReadinessCore

/// The app asked about injuries once and then stopped caring about the answer.
///
/// A tester declared a shoulder, added an overhead press by hand, then set every injury
/// and cleared them again. Through all of it the press sat in their leg day unremarked.
@Suite("What is in the plan that should not be")
struct ProgrammeConflictTests {

    @Test func nothingDeclaredMeansNothingToFlag() {
        #expect(ProgrammeConflicts.among(["Overhead press"], limitations: []).isEmpty)
        #expect(ProgrammeConflicts.among(["Overhead press"], limitations: nil).isEmpty)
    }

    @Test func apressIsFlaggedForABadShoulder() throws {
        let found = ProgrammeConflicts.among(["Leg press", "Overhead press", "Seated cable row"],
                                             limitations: [.shoulders])
        #expect(found.count == 1)
        let conflict = try #require(found.first)
        #expect(conflict.exercise == "Overhead press")
        #expect(conflict.limitations == [.shoulders])
        #expect(conflict.sentence == "loads your shoulders")
    }

    /// What it does not load, it does not flag. Crying wolf over a seated row teaches
    /// people to dismiss the warning that matters.
    @Test func whatIsSafeIsLeftAlone() {
        let found = ProgrammeConflicts.among(["Seated cable row", "Barbell curl", "Calf raise"],
                                             limitations: Set(PhysicalLimitation.allCases))
        #expect(found.isEmpty)
    }

    /// A name the catalogue does not know is not a conflict. Guessing from the word
    /// would be worse than staying quiet.
    @Test func anExerciseWeHaveNeverHeardOfIsNotAccused() {
        #expect(ProgrammeConflicts.among(["Reverse hyper"], limitations: [.lowerBack]).isEmpty)
    }

    @Test func theSameExerciseTwiceIsOneComplaint() {
        let found = ProgrammeConflicts.among(["Overhead press", "Overhead press"],
                                             limitations: [.shoulders])
        #expect(found.count == 1)
    }

    /// Two injuries hitting one movement are named together rather than twice.
    @Test func oneExerciseCanConflictWithMoreThanOneAnswer() throws {
        let found = ProgrammeConflicts.among(["Deadlift"], limitations: [.lowerBack, .knees])
        let conflict = try #require(found.first)
        #expect(conflict.limitations == [.lowerBack, .knees])
        #expect(conflict.sentence == "loads your knees and lower back")
    }
}
