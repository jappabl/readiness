import Testing
@testable import ReadinessCore

/// The sessions the app starts somebody on.
///
/// Rewritten when the presets were. The old ones were five compounds in a row with no
/// isolation, no delts and no arms, and these tests pinned that shape: three plans
/// called Full body, Upper body and Lower body, four to six exercises each. Hao said he
/// would never use the preset for any reason possible. What is kept here is every
/// invariant that was about safety or honesty; what changed is the shape of a session,
/// which was a product decision and not a regression.
@Suite("Training answers change the plan")
struct StarterProgramTests {

    @Test func everySessionIsAWholeSessionRatherThanAListOfCompounds() {
        for equipment in [EquipmentAccess.fullGym, .dumbbells, .bodyweight] {
            let plans = StarterPrograms.make(experience: .regular, equipment: equipment,
                                             limitations: [])
            #expect(!plans.isEmpty)
            for plan in plans {
                // Five to seven movements. Below five it is not a session, above seven
                // it is ninety minutes.
                #expect((4...7).contains(plan.exercises.count),
                        "\(equipment) \(plan.name) had \(plan.exercises.count)")
                #expect(Set(plan.exercises.map(\.name)).count == plan.exercises.count,
                        "\(plan.name) prescribed the same movement twice")
            }
        }
    }

    /// The thing that made the old presets unusable: a chest day with no chest
    /// isolation, a session with nothing for the delts or the arms. Every session now
    /// finishes what it starts.
    @Test func everySessionHasSomethingThatIsNotACompound() {
        for equipment in [EquipmentAccess.fullGym, .dumbbells, .bodyweight] {
            for plan in StarterPrograms.make(experience: .regular, equipment: equipment,
                                             limitations: []) {
                let patterns = plan.exercises.compactMap {
                    ExerciseCatalog.named($0.name)?.pattern
                }
                #expect(patterns.contains { !$0.isCompound },
                        "\(equipment) \(plan.name) is all compounds")
            }
        }
    }

    /// Reps belong to a movement, not to a session. A heavy press and a lateral raise at
    /// the same rep count is how the old presets prescribed sets of five lateral raises.
    @Test func repsAreSetPerExerciseRatherThanPerSession() {
        let plans = StarterPrograms.make(experience: .regular, equipment: .fullGym,
                                         limitations: [])
        let push = plans.first { $0.name == "Push" }
        let reps = try? #require(push).repsPerExercise
        #expect(reps?.count == push?.exercises.count)
        #expect(Set(reps ?? []).count > 1, "every movement got the same rep count")
    }

    // MARK: - Safety

    /// The line is not difficulty, it is what happens when a rep fails with nobody
    /// watching. A barbell bench pins you, a back squat has to be dumped off your back,
    /// a loaded barbell hinge folds a spine that has not learned the pattern.
    @Test func afirstYearLifterIsNeverHandedALiftThatCanPinThem() {
        let gated = ["Barbell bench press", "Back squat", "Deadlift",
                     "Romanian deadlift", "Barbell row", "Overhead press"]
        for equipment in [EquipmentAccess.fullGym, .dumbbells, .bodyweight] {
            let names = StarterPrograms.make(experience: .new, equipment: equipment,
                                             limitations: []).flatMap(\.exercises).map(\.name)
            for lift in gated {
                #expect(!names.contains(lift), "a beginner was prescribed \(lift)")
            }
        }
    }

    /// And the same list is not offered as a swap either, which would have been the hole
    /// in gating only the preset.
    @Test func norIsOneOfferedAsASubstitute() throws {
        let press = try #require(ExerciseCatalog.named("Machine chest press"))
        let swaps = ExerciseCatalog.alternatives(to: press, equipment: .fullGym,
                                                 limitations: [], experience: .new)
        #expect(!swaps.isEmpty)
        #expect(!swaps.contains { $0.name == "Barbell bench press" })
        #expect(swaps.allSatisfy { $0.pattern == .horizontalPress })
    }

    @Test func somebodyWithAYearBehindThemGetsTheBarbell() {
        let names = StarterPrograms.make(experience: .regular, equipment: .fullGym,
                                         limitations: []).flatMap(\.exercises).map(\.name)
        #expect(names.contains("Barbell bench press"))
        #expect(names.contains("Back squat"))
    }

    @Test func extraExercisesStillRespectEveryReportedLimit() {
        for equipment in [EquipmentAccess.fullGym, .dumbbells, .bodyweight] {
            for limit in PhysicalLimitation.allCases {
                let plans = StarterPrograms.make(experience: .regular, equipment: equipment,
                                                 limitations: [limit])
                #expect(plans.flatMap(\.exercises).allSatisfy { !$0.loadedAreas.contains(limit) },
                        "\(equipment) prescribed something loading \(limit)")
            }
        }
    }

    @Test func limitationsRemoveConflictingStarterExercisesAndSubstitutions() {
        // Ruling out all three used to leave nothing, because every movement in the
        // catalogue claimed a back, a knee or a shoulder. It claimed too much: a seated
        // row does not load a shoulder and a calf raise does not load a knee. What is
        // left for somebody carrying all three is small and seated, which is the honest
        // answer, and a good deal more use than an empty screen.
        let everything = StarterPrograms.make(experience: .new, equipment: .fullGym,
                                              limitations: Set(PhysicalLimitation.allCases))
        let left = everything.flatMap(\.exercises).map(\.name)
        #expect(!left.isEmpty)
        #expect(left.allSatisfy { name in
            ExerciseCatalog.named(name)?.loads.isEmpty == true
        }, "something that loads a restricted joint survived: \(left)")
        #expect(!StarterPrograms.allowedExerciseNames(equipment: .dumbbells,
                                                      limitations: [.shoulders])
            .contains("Dumbbell bench press"))
        #expect(!StarterPrograms.allowedExerciseNames(equipment: .bodyweight, limitations: [])
            .contains("Barbell row"))
    }

    // MARK: - Equipment

    @Test func dumbbellsNeverPrescribeBarbellsOrMachines() {
        let plans = StarterPrograms.make(experience: .new, equipment: .dumbbells,
                                         limitations: [])
        #expect(!plans.isEmpty)
        #expect(plans.flatMap(\.exercises).allSatisfy {
            $0.requiredEquipment == .dumbbells || $0.requiredEquipment == .bodyweight
        })
    }

    @Test func noEquipmentMeansNoLoadOrMachineRequirement() {
        let exercises = StarterPrograms.make(experience: .regular, equipment: .bodyweight,
                                             limitations: []).flatMap(\.exercises)
        #expect(!exercises.isEmpty)
        #expect(exercises.allSatisfy { $0.requiredEquipment == .bodyweight && $0.increment == 0 })
    }

    // MARK: - The week

    /// Frequency decides the shape, which is the thing that separates a programme from a
    /// list of exercises. Two days of half an upper/lower rotation trains each half once
    /// a fortnight.
    @Test("the week matches how often they actually train", arguments: [
        (TrainingFrequency.rarely, 2), (.few, 2), (.most, 5), (.daily, 3),
    ])
    func weekShape(frequency: TrainingFrequency, sessions: Int) throws {
        let split = try #require(StarterPrograms.recommended(
            experience: .regular, equipment: .fullGym, limitations: [], frequency: frequency))
        #expect(split.sessions.count == sessions, "\(frequency) got \(split.sessions.count)")
    }

    @Test func everyCombinationProducesSomethingRatherThanAnEmptyTrainTab() {
        for frequency in TrainingFrequency.allCases {
            for experience in TrainingExperience.allCases {
                for equipment in EquipmentAccess.allCases {
                    let split = StarterPrograms.recommended(
                        experience: experience, equipment: equipment,
                        limitations: [], frequency: frequency)
                    #expect(split?.sessions.isEmpty == false,
                            "\(frequency) \(experience) \(equipment) got nothing")
                }
            }
        }
    }

    @Test func noPlanBeforeTheInjuryQuestionIsAnswered() {
        #expect(StarterPrograms.recommended(experience: .regular, equipment: .fullGym,
                                            limitations: nil, frequency: .few) == nil)
        #expect(StarterPrograms.splits(experience: .regular, equipment: .fullGym,
                                       limitations: nil).isEmpty)
    }

    @Test func experienceChangesVolumeAndEffortAndProgression() {
        let novice = StarterPrograms.make(experience: .new, equipment: .fullGym, limitations: [])
        let experienced = StarterPrograms.make(experience: .experienced, equipment: .fullGym,
                                               limitations: [])
        #expect(novice[0].sets == 2 && novice[0].rir == 3)
        #expect(experienced[0].sets == 3 && experienced[0].rir == 2)
        #expect(novice[0].progression == .linear)
        #expect(experienced[0].progression == .plannedBlocks)
    }

    @Test func currentProfileLimitsOverrideTheOnboardingSnapshot() {
        var answers = OnboardingAnswers()
        answers.equipment = .fullGym; answers.limitations = []
        let restricted = CoachProfileSummary(health: HealthProfile(), answers: answers,
                                             limitations: "Shoulders")
        #expect(restricted.allowedExercises?.contains("Barbell bench press") == false)
        answers.limitations = [.knees]
        let cleared = CoachProfileSummary(health: HealthProfile(), answers: answers,
                                          limitations: "")
        #expect(cleared.allowedExercises?.contains("Back squat") == true)
        let unknown = PhysicalLimitation.from(profileText: "Ankle fracture")
        #expect(unknown == nil)
        #expect(StarterPrograms.make(experience: .new, equipment: .fullGym,
                                     limitations: unknown).isEmpty)
        let unclassified = CoachProfileSummary(health: HealthProfile(), answers: answers,
                                               limitations: "Ankle fracture")
        #expect(unclassified.allowedExercises == [])
    }
}

/// What an injury leaves behind.
///
/// A tester came back from a shoulder injury, told the app, and was given one session
/// for ever: Lower. No rows, no pulldowns, no arms, no chest. Every upper-body movement
/// in the catalogue claimed the shoulder, curls included, and the filter is a hard
/// exclusion, so declaring the injury deleted half of training. He wrote that the app's
/// one job was not handing him something that hurts, and closed it.
@Suite("An injury narrows training rather than deleting it")
struct InjuryStillLeavesAProgrammeTests {

    @Test("every limitation still leaves something for the upper body",
          arguments: [PhysicalLimitation.shoulders, .lowerBack, .knees])
    func upperBodySurvives(_ limit: PhysicalLimitation) throws {
        let split = try #require(StarterPrograms.recommended(
            experience: .experienced, equipment: .fullGym,
            limitations: [limit], frequency: .few))
        #expect(split.sessions.count == 2, "\(limit) collapsed the week to \(split.sessions.count)")
        let names = split.sessions.flatMap(\.exercises).map(\.name)
        #expect(!names.isEmpty)
    }

    /// The point of the filter still holds: what it excludes, it excludes.
    @Test func aShoulderStillRulesOutPressingAndHanging() {
        let allowed = ExerciseCatalog.available(equipment: .fullGym, limitations: [.shoulders],
                                                experience: .experienced).map(\.name)
        for banned in ["Barbell bench press", "Overhead press", "Machine shoulder press",
                       "Push-up", "Pull-up", "Chin-up", "Lateral raise", "Dumbbell fly"] {
            #expect(!allowed.contains(banned), "\(banned) was offered to a bad shoulder")
        }
    }

    /// And what it does not exclude is enough to train with.
    @Test func aShoulderStillLeavesRowsAndArms() {
        let allowed = ExerciseCatalog.available(equipment: .fullGym, limitations: [.shoulders],
                                                experience: .experienced).map(\.name)
        for kept in ["Seated cable row", "Chest-supported row", "Face pull",
                     "Barbell curl", "Triceps pushdown"] {
            #expect(allowed.contains(kept), "\(kept) was withheld from a bad shoulder")
        }
    }

    /// "None" is the word the app itself writes into the Profile field, and its own
    /// parser could not read it. Unreadable means different things at different call
    /// sites, so the same answer both emptied and unlocked the catalogue.
    @Test func theAppCanReadItsOwnWordForNoInjuries() {
        #expect(PhysicalLimitation.from(profileText: "None") == [])
        #expect(PhysicalLimitation.from(profileText: "none") == [])
        #expect(PhysicalLimitation.from(profileText: "") == [])
        #expect(PhysicalLimitation.from(profileText: "Shoulders") == [.shoulders])
        #expect(PhysicalLimitation.from(profileText: "Ankle fracture") == nil)
    }
}
