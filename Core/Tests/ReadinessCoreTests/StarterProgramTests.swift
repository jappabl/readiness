import Testing
@testable import ReadinessCore

@Suite("Training answers change the plan")
struct StarterProgramTests {
    @Test func unrestrictedPresetsHaveEnoughVariedExercisesToEdit() {
        for equipment in [EquipmentAccess.fullGym, .dumbbells, .bodyweight] {
            let plans = StarterPrograms.make(experience: .regular, equipment: equipment, limitations: [])
            #expect(plans.count == 3)
            for plan in plans {
                #expect((4...6).contains(plan.exercises.count))
                #expect(Set(plan.exercises.map(\.name)).count == plan.exercises.count)
            }
            let full = plans.first { $0.name == "Full body" }!
            #expect(full.exercises.contains { $0.muscle.isLowerBody })
            #expect(full.exercises.contains { $0.muscle == .chest })
            #expect(full.exercises.contains { $0.muscle == .back })
        }
    }

    @Test func extraExercisesStillRespectEveryReportedLimit() {
        for equipment in [EquipmentAccess.fullGym, .dumbbells, .bodyweight] {
            for limit in PhysicalLimitation.allCases {
                let plans = StarterPrograms.make(experience: .regular, equipment: equipment, limitations: [limit])
                #expect(plans.flatMap(\.exercises).allSatisfy { !$0.loadedAreas.contains(limit) })
            }
        }
    }

    @Test func presetSplitsContainCompleteSessionsAndNeverInventAnUnavailableHalf() {
        let splits = StarterPrograms.splits(experience: .regular, equipment: .fullGym, limitations: [])
        #expect(splits.map(\.name) == ["Full body", "Upper / lower"])
        #expect(splits[0].sessions.map(\.name) == ["Full body"])
        #expect(splits[1].sessions.map(\.name) == ["Upper body", "Lower body"])
        let limited = StarterPrograms.splits(experience: .regular, equipment: .bodyweight, limitations: [.shoulders])
        #expect(limited.allSatisfy { $0.sessions.allSatisfy { !$0.exercises.isEmpty } })
        #expect(StarterPrograms.splits(experience: .regular, equipment: .fullGym, limitations: nil).isEmpty)
    }

    @Test func currentProfileLimitsOverrideTheOnboardingSnapshot() {
        var answers = OnboardingAnswers()
        answers.equipment = .fullGym; answers.limitations = []
        let restricted = CoachProfileSummary(health: HealthProfile(), answers: answers, limitations: "Shoulders")
        #expect(restricted.allowedExercises?.contains("Bench press") == false)
        answers.limitations = [.knees]
        let cleared = CoachProfileSummary(health: HealthProfile(), answers: answers, limitations: "")
        #expect(cleared.allowedExercises?.contains("Back squat") == true)
        let unknown = PhysicalLimitation.from(profileText: "Ankle fracture")
        #expect(unknown == nil)
        #expect(StarterPrograms.make(experience: .new, equipment: .fullGym, limitations: unknown).isEmpty)
        let unclassified = CoachProfileSummary(health: HealthProfile(), answers: answers, limitations: "Ankle fracture")
        #expect(unclassified.allowedExercises == [])
    }

    @Test func dumbbellsNeverPrescribeBarbellsMachinesOrBenches() {
        let plans = StarterPrograms.make(experience: .new, equipment: .dumbbells, limitations: [])
        #expect(!plans.isEmpty)
        let names = plans.flatMap(\.exercises).map(\.name)
        #expect(names.contains("Dumbbell floor press"))
        #expect(!names.contains("Bench press") && !names.contains("Leg press") && !names.contains("Back squat"))
        #expect(plans.flatMap(\.exercises).allSatisfy { $0.requiredEquipment == .dumbbells || $0.requiredEquipment == .bodyweight })
    }

    @Test func noEquipmentMeansNoLoadOrMachineRequirement() {
        let exercises = StarterPrograms.make(experience: .regular, equipment: .bodyweight, limitations: []).flatMap(\.exercises)
        #expect(!exercises.isEmpty)
        #expect(exercises.allSatisfy { $0.requiredEquipment == .bodyweight && $0.increment == 0 })
    }

    @Test func experienceChangesVolumeEffortAndProgressionButNotAvailablePlates() {
        let novice = StarterPrograms.make(experience: .new, equipment: .fullGym, limitations: [])
        let experienced = StarterPrograms.make(experience: .experienced, equipment: .fullGym, limitations: [])
        #expect(novice[0].sets == 2 && novice[0].rir == 3)
        #expect(experienced[0].sets == 3 && experienced[0].rir == 2)
        #expect(novice[0].progression == .linear)
        #expect(experienced[0].progression == .plannedBlocks)
        #expect(novice[0].exercises.map(\.increment) == experienced[0].exercises.map(\.increment))
    }

    @Test func limitationsRemoveConflictingStarterExercisesAndSubstitutions() {
        let exercises = StarterPrograms.make(experience: .new, equipment: .fullGym, limitations: [.lowerBack, .knees, .shoulders]).flatMap(\.exercises)
        #expect(exercises.isEmpty)
        #expect(!StarterPrograms.allowedExerciseNames(equipment: .dumbbells, limitations: [.shoulders]).contains("Dumbbell floor press"))
        #expect(!StarterPrograms.allowedExerciseNames(equipment: .bodyweight, limitations: []).contains("Barbell row"))
    }
}
