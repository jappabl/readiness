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

    @Test func nonliftingCombinationSkipsEquipment() {
        var flow = OnboardingConversation()
        flow.toggleGoal(.feelBetter)
        flow.toggleGoal(.loseFat)
        flow.confirmGoals()
        flow.chooseFrequency(.rarely)
        flow.chooseExperience(.new)
        flow.confirmObstacles()
        flow.confirmLimitations(none: true)
        #expect(flow.step == .units)
        #expect(flow.answers.equipment == nil)
        #expect(flow.answers.isComplete)
        flow.chooseEquipment(.fullGym)
        #expect(flow.answers.equipment == nil)
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

    @Test func removingLastLiftingGoalClearsEquipment() {
        var answers = OnboardingAnswers()
        answers.setGoals([.buildMuscle, .feelBetter])
        answers.equipment = .fullGym
        answers.setGoals([.feelBetter, .loseFat])
        #expect(!answers.impliesLifting)
        #expect(answers.equipment == nil)
    }

    @Test func mixedGoalsContributeHomeCardsWithoutDuplicates() {
        let blocks = HomeComposition.blocks(for: Set([TrainingGoal.buildMuscle, .loseFat, .feelBetter]), hasProgram: false)
        #expect(blocks == [.programPrompt, .nutrition, .weightTrend, .sleepQuality, .movement, .healthMonitor])
        let withProgram = HomeComposition.blocks(for: Set([TrainingGoal.getStronger, .buildMuscle]), hasProgram: true)
        #expect(withProgram == [.session, .nutrition, .weightTrend, .healthMonitor])
    }

    @Test func nonliftingHomeDoesNotAddAProgramPrompt() {
        let blocks = HomeComposition.blocks(for: Set([TrainingGoal.loseFat, .feelBetter]), hasProgram: false)
        #expect(blocks == [.nutrition, .weightTrend, .sleepQuality, .movement, .healthMonitor])
    }
}
