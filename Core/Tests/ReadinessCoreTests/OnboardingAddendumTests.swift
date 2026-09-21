import Foundation
import Testing
@testable import ReadinessCore

@Suite("Onboarding addendum")
struct OnboardingAddendumTests {
    @Test func goalAndFrequencyAreNotEnoughToFinish() {
        var answers = OnboardingAnswers()
        answers.goal = .buildMuscle
        answers.frequency = .few
        #expect(!answers.isComplete)
    }

    @Test(arguments: TrainingGoal.allCases)
    func equipmentIsOnlyAskedForLifting(_ goal: TrainingGoal) {
        var flow = OnboardingConversation()
        flow.toggleGoal(goal); flow.confirmGoals()
        flow.chooseFrequency(.few)
        #expect(flow.step == .experience)
        flow.chooseExperience(.new)
        #expect(flow.step == .obstacles)
        flow.confirmObstacles()
        #expect(flow.step == .limitations)
        flow.confirmLimitations(none: true)
        if goal.impliesLifting {
            #expect(flow.step == .equipment)
            #expect(!flow.answers.isComplete)
            flow.chooseEquipment(.dumbbells)
        } else {
            #expect(flow.answers.equipment == nil)
        }
        #expect(flow.step == .units)
        #expect(flow.answers.isComplete)
    }

    @Test func limitsSurviveEditingAndNoneClearsThem() {
        var flow = throughExperience()
        flow.confirmObstacles()
        flow.toggleLimitation(.shoulders)
        flow.toggleLimitation(.knees)
        flow.confirmLimitations()
        #expect(flow.answers.limitationsText == "Knees, Shoulders")
        flow.editAnswer(id: flow.latestEditableAnswerID!)
        #expect(flow.step == .limitations)
        #expect(flow.answers.limitations == [.knees, .shoulders])
        flow.confirmLimitations(none: true)
        #expect(flow.answers.limitations == [])
        #expect(flow.answers.limitationsText == "")
    }

    @Test func editingExperienceReplacesOnlyTheLastAnswer() {
        var flow = throughExperience()
        let oldID = flow.latestEditableAnswerID!
        flow.editAnswer(id: oldID)
        #expect(flow.step == .experience)
        flow.chooseExperience(.experienced)
        #expect(flow.answers.experience == .experienced)
        #expect(flow.turns.filter { $0.isUser && $0.text == TrainingExperience.new.title }.isEmpty)
        flow.confirmObstacles()
        flow.editAnswer(id: oldID)
        #expect(flow.step == .limitations)
    }

    @Test func detailsAlreadyKnownLocallySurviveAFlowThatDoesNotAskAgain() {
        var previous = OnboardingAnswers()
        previous.healthDetails = HealthProfile(heightCM: 175, biologicalSex: .female)
        var next = OnboardingAnswers()
        let unchanged = next.preservingHealthDetails(from: previous)
        #expect(unchanged.healthDetails == previous.healthDetails)
        next.healthDetails = HealthProfile(dateOfBirth: DateComponents(year: 1995, month: 9, day: 19))
        let merged = next.preservingHealthDetails(from: previous)
        #expect(merged.healthDetails?.heightCM == 175)
        #expect(merged.healthDetails?.biologicalSex == .female)
        #expect(merged.healthDetails?.dateOfBirth?.year == 1995)
    }

    @Test func oldSavedAnswersDecodeWithoutInventingNewAnswers() throws {
        let data = Data(#"{"goal":"feelBetter","frequency":"few","obstacles":["sleep"],"unitsAreMetric":true}"#.utf8)
        let answers = try JSONDecoder().decode(OnboardingAnswers.self, from: data)
        #expect(answers.goal == .feelBetter)
        #expect(answers.obstacles == [.sleep])
        #expect(answers.experience == nil && answers.equipment == nil && answers.limitations == nil)
        #expect(answers.healthDetails == nil)
        #expect(!answers.isComplete)
        #expect(try JSONDecoder().decode(OnboardingAnswers.self, from: JSONEncoder().encode(answers)) == answers)
    }

    @Test func knownHealthDetailsSkipFallback() {
        var flow = readyForHealth()
        flow.beginReading()
        flow.finishReading(hasHealthData: true, profile: knownProfile, today: today)
        #expect(flow.step == .ready)
        #expect(flow.missingHealthFields.isEmpty)
    }

    @Test func fallbackOnlyAsksForMissingFieldsAndCannotReplaceKnownValues() {
        var flow = readyForHealth()
        flow.beginReading()
        flow.finishReading(hasHealthData: true,
            profile: HealthProfile(heightCM: 175, biologicalSex: .female), today: today)
        #expect(flow.step == .healthDetails)
        #expect(flow.missingHealthFields == [.dateOfBirth])
        let manual = HealthProfile(heightCM: 200, dateOfBirth: DateComponents(year: 1995, month: 9, day: 19), biologicalSex: .male)
        let accepted = flow.submitHealthDetails(manual, today: today)
        #expect(accepted)
        #expect(flow.answers.healthDetails?.heightCM == nil)
        #expect(flow.answers.healthDetails?.biologicalSex == nil)
        #expect(flow.answers.healthDetails?.ageYears(on: today) == 30)
        #expect(flow.step == .ready)
        #expect(!flow.turns.contains { $0.text.contains("1995") })
    }

    @Test func partialManualAnswersCanFinishAndInvalidValuesDoNotDisappearSilently() {
        var flow = readyForHealth()
        flow.beginReading()
        flow.finishReading(hasHealthData: false, today: today)
        #expect(flow.missingHealthFields == [.height, .dateOfBirth, .biologicalSex])
        let invalidAccepted = flow.submitHealthDetails(HealthProfile(heightCM: 3), today: today)
        #expect(!invalidAccepted)
        #expect(flow.step == .healthDetails)
        let partialAccepted = flow.submitHealthDetails(HealthProfile(heightCM: 170), today: today)
        #expect(partialAccepted)
        #expect(flow.step == .ready)
        #expect(flow.answers.healthDetails?.heightCM == 170)
        #expect(flow.answers.healthDetails?.dateOfBirth == nil)
    }

    @Test func skippedHealthAndSkippedDetailsStillComplete() {
        var flow = readyForHealth()
        flow.skipHealth(today: today)
        #expect(flow.step == .healthDetails)
        flow.skipHealthDetails()
        #expect(flow.step == .ready)
        #expect(flow.answers.isComplete)
        #expect(flow.answers.healthDetails == nil)
        #expect(flow.latestEditableAnswerID == nil)
    }

    private var today: Date { Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 9, day: 18))! }
    private var knownProfile: HealthProfile {
        HealthProfile(heightCM: 175, dateOfBirth: DateComponents(year: 1995, month: 9, day: 19), biologicalSex: .female)
    }
    private func throughExperience() -> OnboardingConversation {
        var flow = OnboardingConversation()
        flow.toggleGoal(.buildMuscle); flow.confirmGoals(); flow.chooseFrequency(.few); flow.chooseExperience(.new)
        return flow
    }
    private func readyForHealth() -> OnboardingConversation {
        var flow = throughExperience()
        flow.confirmObstacles(); flow.confirmLimitations(none: true)
        flow.chooseEquipment(.fullGym); flow.chooseUnits(metric: true)
        flow.chooseWatch(wearsOne: true)
        return flow
    }
}
