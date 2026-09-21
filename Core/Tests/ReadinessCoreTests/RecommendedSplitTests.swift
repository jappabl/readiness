import Testing
@testable import ReadinessCore

/// Picking the split from what onboarding already knows.
///
/// The gap this closes: onboarding asks experience, equipment and limitations, which is
/// exactly and only what `splits(experience:equipment:limitations:)` takes, and then
/// built nothing. The user answered four questions whose whole purpose was a training
/// plan and landed on a card asking them to build one.
///
/// Frequency is the deciding input, and it is the one the split function never saw. Two
/// sessions a week cannot cover an upper/lower rotation properly, and six sessions of
/// the same full body day is a lot of squatting.
@Suite("Choosing a starting split")
struct RecommendedSplitTests {

    private func recommended(_ frequency: TrainingFrequency,
                             experience: TrainingExperience = .regular,
                             equipment: EquipmentAccess = .fullGym) -> String? {
        StarterPrograms.recommended(experience: experience, equipment: equipment,
                                    limitations: [], frequency: frequency)?.name
    }

    @Test("two days a week is two full body days, not half a rotation")
    func infrequentGetsFullBody() {
        // Half an upper/lower rotation twice a week means each half is trained once a
        // fortnight, which is not a programme, it is a coincidence. Two full body days
        // that lead on different patterns cover everything twice.
        #expect(recommended(.rarely) == "Full body")
    }

    /// Three or four days is upper/lower. Four days is the textbook version and three
    /// runs it as upper, lower, upper, which still trains everything at least once and
    /// most of it twice. The app's band covers both, so it has to pick the one that is
    /// right at the top of the range.
    @Test("three or four days is an upper/lower rotation")
    func moderateGetsUpperLower() {
        #expect(recommended(.few) == "Upper / lower")
    }

    /// Five is where the standard answer stops being two sessions. Push, pull and legs
    /// plus upper and lower is how a fifth and sixth session's worth of volume fits
    /// into five days; six days is push/pull/legs twice.
    @Test("five days and up is push, pull, legs")
    func frequentGetsASplit() {
        #expect(recommended(.most) == "Push / pull / legs + upper / lower")
        #expect(recommended(.daily) == "Push / pull / legs")
    }

    @Test("with nothing to lift there is still a plan")
    func bodyweightStillGetsOne() {
        #expect(recommended(.few, equipment: .bodyweight) != nil)
        #expect(recommended(.most, equipment: .bodyweight) != nil)
    }

    @Test("every combination produces something rather than nothing",
          arguments: TrainingFrequency.allCases)
    func neverEmptyHanded(_ frequency: TrainingFrequency) {
        // Landing on an empty Train tab after answering everything is the failure this
        // exists to stop, so no combination may return nil.
        for experience in TrainingExperience.allCases {
            for equipment in EquipmentAccess.allCases {
                let split = StarterPrograms.recommended(
                    experience: experience, equipment: equipment,
                    limitations: [], frequency: frequency)
                #expect(split != nil, "\(frequency) \(experience) \(equipment) got nothing")
                #expect(split?.sessions.isEmpty == false,
                        "\(frequency) \(experience) \(equipment) got an empty plan")
            }
        }
    }

    @Test("no plan before the injury question has been answered")
    func unknownLimitationsMeansNoPlan() {
        // Nil is "not asked yet", and the catalog deliberately yields nothing for it.
        // Prescribing a back squat before knowing about somebody's back is the one
        // mistake here worth refusing to make.
        #expect(StarterPrograms.recommended(experience: .regular, equipment: .fullGym,
                                            limitations: nil, frequency: .few) == nil)
    }

    @Test("one limitation still leaves a plan")
    func oneLimitationStillLeavesAPlan() {
        for limitation in PhysicalLimitation.allCases {
            let split = StarterPrograms.recommended(
                experience: .regular, equipment: .fullGym,
                limitations: [limitation], frequency: .few)
            #expect(split?.sessions.first?.exercises.isEmpty == false,
                    "\(limitation) left nothing to do")
        }
    }

    @Test("somebody who ruled out everything gets no plan, and that is the honest answer")
    func everythingRuledOutMeansNoPlan() {
        // Every exercise in the catalog loads a back, a knee or a shoulder. Somebody
        // who has restricted all three has no safe starting programme, and inventing
        // one for them is the single worst thing this could do.
        #expect(StarterPrograms.recommended(
            experience: .regular, equipment: .fullGym,
            limitations: Set(PhysicalLimitation.allCases), frequency: .few) == nil)
    }
}
