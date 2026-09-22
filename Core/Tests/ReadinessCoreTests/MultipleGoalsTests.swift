import Foundation
import Testing
@testable import ReadinessCore

@Suite("Multiple onboarding goals")
struct MultipleGoalsTests {
    @Test func selectingSeveralGoalsWaitsForConfirmation() {
        var flow = OnboardingConversation()
        flow.toggleGoal(.feelBetter)
        flow.toggleGoal(.buildMuscle)
        #expect(flow.step == .goal)
        #expect(flow.turns.count == 2)
        #expect(flow.answers.selectedGoals == [.feelBetter, .buildMuscle])
        flow.confirmGoals()
        #expect(flow.step == .frequency)
        #expect(flow.turns[2].text == "Build muscle, Feel better")
        #expect(flow.turns[2].reaction == .muscle)
        #expect(flow.turns.count == 4)
        flow.toggleGoal(.loseFat)
        flow.confirmGoals()
        #expect(flow.answers.selectedGoals == [.feelBetter, .buildMuscle])
        #expect(flow.turns.count == 4)
    }

    @Test func emptySelectionCannotContinue() {
        var flow = OnboardingConversation()
        flow.confirmGoals()
        flow.toggleGoal(.getStronger)
        flow.toggleGoal(.getStronger)
        flow.confirmGoals()
        #expect(flow.step == .goal)
        #expect(flow.turns.count == 2)
        #expect(flow.answers.selectedGoals.isEmpty)
        #expect(!flow.answers.isComplete)
    }

    @Test func editedSelectionIsRetainedAndCanRemoveOneGoal() {
        var flow = OnboardingConversation()
        flow.toggleGoal(.loseFat)
        flow.toggleGoal(.getStronger)
        flow.confirmGoals()
        flow.editAnswer(id: flow.latestEditableAnswerID!)
        #expect(flow.answers.selectedGoals == [.getStronger, .loseFat])
        flow.toggleGoal(.getStronger)
        flow.confirmGoals()
        #expect(flow.answers.selectedGoals == [.loseFat])
        #expect(flow.turns[2].text == "Lose fat")
        #expect(flow.turns.count == 4)
    }

    @Test(arguments: [
        [TrainingGoal.feelBetter, .buildMuscle],
        [.loseFat, .getStronger],
        [.getStronger, .buildMuscle, .loseFat, .feelBetter]
    ])
    func anyLiftingGoalRequiresEquipment(_ goals: [TrainingGoal]) {
        var flow = OnboardingConversation()
        for goal in goals { flow.toggleGoal(goal) }
        flow.confirmGoals()
        flow.chooseFrequency(.few)
        flow.chooseExperience(.regular)
        flow.confirmObstacles()
        flow.confirmLimitations(none: true)
        #expect(flow.step == .equipment)
        #expect(!flow.answers.isComplete)
        flow.chooseEquipment(.dumbbells)
        #expect(flow.step == .units)
        #expect(flow.answers.isComplete)
    }

    /// Somebody here to lose fat and feel better still gets a training plan, so they are
    /// still asked what they can train with.
    @Test func everyGoalIsAskedWhatTheyCanTrainWith() {
        var flow = OnboardingConversation()
        flow.toggleGoal(.feelBetter)
        flow.toggleGoal(.loseFat)
        flow.confirmGoals()
        flow.chooseFrequency(.rarely)
        flow.chooseExperience(.new)
        flow.confirmObstacles()
        flow.confirmLimitations(none: true)
        #expect(flow.step == .equipment)
        #expect(!flow.answers.isComplete)
        flow.chooseEquipment(.dumbbells)
        #expect(flow.answers.equipment == .dumbbells)
        #expect(flow.step == .units)
        #expect(flow.answers.isComplete)
    }

    @Test func selectedGoalsRoundTripAndLegacyAnswersStillLoad() throws {
        var answers = OnboardingAnswers()
        answers.setGoals([.buildMuscle, .loseFat])
        let restored = try JSONDecoder().decode(OnboardingAnswers.self, from: JSONEncoder().encode(answers))
        #expect(restored.selectedGoals == [.buildMuscle, .loseFat])
        #expect(restored.goal != nil, "Keep the existing profile completion marker compatible")
        let old = Data(#"{"goal":"feelBetter","obstacles":[],"unitsAreMetric":false}"#.utf8)
        let legacy = try JSONDecoder().decode(OnboardingAnswers.self, from: old)
        #expect(legacy.selectedGoals == [.feelBetter])
    }

    /// Changing your mind about why you are training does not change what is in your
    /// room. Dropping the lifting goals used to wipe the equipment answer, which was the
    /// other half of never asking for it.
    @Test func changingGoalsKeepsWhatTheyToldUsTheyOwn() {
        var answers = OnboardingAnswers()
        answers.setGoals([.buildMuscle, .feelBetter])
        answers.equipment = .fullGym
        answers.setGoals([.feelBetter, .loseFat])
        #expect(answers.equipment == .fullGym)
    }

    @Test func mixedGoalsContributeHomeCardsWithoutDuplicates() {
        let blocks = HomeComposition.blocks(for: Set([TrainingGoal.buildMuscle, .loseFat, .feelBetter]), hasProgram: false)
        // Sleep debt joins every goal: it is a standing balance rather than something
        // one kind of training cares about, and the card shows nothing when there is
        // nothing owed.
        #expect(blocks == [.programPrompt, .nutrition, .weightTrend, .sleepDebt,
                           .sleepQuality, .movement])
        let withProgram = HomeComposition.blocks(for: Set([TrainingGoal.getStronger, .buildMuscle]), hasProgram: true)
        #expect(withProgram == [.session, .sleepDebt, .nutrition, .weightTrend])
    }

    @Test func nonliftingHomeDoesNotAddAProgramPrompt() {
        let blocks = HomeComposition.blocks(for: Set([TrainingGoal.loseFat, .feelBetter]), hasProgram: false)
        #expect(blocks == [.nutrition, .weightTrend, .sleepDebt, .sleepQuality, .movement])
    }
}
