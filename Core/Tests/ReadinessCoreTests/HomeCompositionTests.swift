import Testing
@testable import ReadinessCore

/// The product rule this encodes: the barbell angle cannot be the front page for
/// everybody. Someone who came here to sleep better should not open the app to a
/// prescribed back squat.
@Suite("Composing the home screen for a goal")
struct HomeCompositionTests {

    @Test("no goal produces an empty screen")
    func neverEmpty() {
        for goal in TrainingGoal.allCases {
            #expect(HomeComposition.blocks(for: goal, hasProgram: false).count > 1,
                    "\(goal) needs something on it")
        }
    }

    @Test("a session is never offered to someone with no programme")
    func noSessionWithoutProgram() {
        for goal in TrainingGoal.allCases {
            let blocks = HomeComposition.blocks(for: goal, hasProgram: false)
            #expect(!blocks.contains(.session), "\(goal) promised a session that does not exist")
        }
    }

    @Test("lifting leads for the goals that are about lifting")
    func liftingLeadsWhenItShould() {
        #expect(HomeComposition.blocks(for: .getStronger, hasProgram: true).first == .session)
        #expect(HomeComposition.blocks(for: .buildMuscle, hasProgram: true).first == .session)
    }

    @Test("lifting never leads for the goals that are not")
    func liftingNeverLeadsOtherwise() {
        for goal in [TrainingGoal.loseFat, .feelBetter] {
            let blocks = HomeComposition.blocks(for: goal, hasProgram: true)
            #expect(blocks.first != .session, "\(goal) opened on a barbell")
            #expect(blocks.contains(.session), "\(goal) should still reach its programme")
        }
    }

    @Test("fat loss leads with the numbers that decide fat loss")
    func fatLossLeadsWithEnergy() {
        let blocks = HomeComposition.blocks(for: .loseFat, hasProgram: true)
        #expect(blocks.first == .nutrition)
        #expect(blocks.contains(.weightTrend))
        #expect(blocks.contains(.nutrition))
    }

    @Test("feeling better leads with sleep and movement, not food")
    func healthLeadsWithSleep() {
        let blocks = HomeComposition.blocks(for: .feelBetter, hasProgram: true)
        #expect(blocks.first == .sleepQuality)
        #expect(blocks.contains(.movement))
        #expect(!blocks.contains(.nutrition), "nobody asked to be put on a diet")
    }

    @Test("building muscle surfaces protein, losing fat surfaces it too")
    func proteinWhereItMatters() {
        #expect(HomeComposition.blocks(for: .buildMuscle, hasProgram: true).contains(.nutrition))
        #expect(HomeComposition.blocks(for: .loseFat, hasProgram: true).contains(.nutrition))
    }

    @Test("a block never appears twice")
    func noDuplicates() {
        for goal in TrainingGoal.allCases {
            for hasProgram in [true, false] {
                let blocks = HomeComposition.blocks(for: goal, hasProgram: hasProgram)
                #expect(Set(blocks).count == blocks.count, "\(goal) repeated a block")
            }
        }
    }
}

extension HomeCompositionTests {

    @Test("a lifting goal with nothing to lift asks, rather than showing nothing")
    func liftingGoalWithoutProgramAsks() {
        for goal in [TrainingGoal.getStronger, .buildMuscle] {
            let blocks = HomeComposition.blocks(for: goal, hasProgram: false)
            #expect(blocks.first == .programPrompt, "\(goal) should ask for a programme")
        }
    }

    @Test("the other goals stand on their own without a programme")
    func nonLiftingGoalsNeedNoProgram() {
        for goal in [TrainingGoal.loseFat, .feelBetter] {
            let blocks = HomeComposition.blocks(for: goal, hasProgram: false)
            #expect(!blocks.contains(.programPrompt), "\(goal) should not be nagged to lift")
        }
    }
}
