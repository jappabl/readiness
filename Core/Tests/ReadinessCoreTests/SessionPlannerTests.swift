import Testing
@testable import ReadinessCore

private let squat = PlannedExercise(name: "Back squat", muscleGroup: .quads, sets: 5, reps: 5,
                                    workingWeight: 315, increment: 10, rir: 2)
private let bench = PlannedExercise(name: "Bench press", muscleGroup: .chest, sets: 4, reps: 5,
                                    workingWeight: 185, increment: 5, rir: 2)

@Suite("Applying adjustments to a planned session")
struct SessionPlannerTests {

    @Test("proceeding as planned changes nothing")
    func proceedChangesNothing() {
        let out = SessionPlanner.apply([.proceedAsPlanned], to: [squat])
        #expect(out[0].sets == 5)
        #expect(out[0].load == 315)
        #expect(out[0].rir == 2)
        #expect(!out[0].changed)
    }

    @Test("cutting sets by 20% takes five sets to four")
    func setsAreCut() {
        let out = SessionPlanner.apply([.reduceWorkingSets(percent: 20)], to: [squat])
        #expect(out[0].sets == 4)
    }

    @Test("a session is never reduced to zero sets")
    func neverZeroSets() {
        let single = PlannedExercise(name: "Curl", muscleGroup: .arms, sets: 1, reps: 10,
                                     workingWeight: 40, increment: 5, rir: 2)
        let out = SessionPlanner.apply([.reduceWorkingSets(percent: 90)], to: [single])
        #expect(out[0].sets == 1)
    }

    @Test("capping effort only ever moves further from failure")
    func capOnlyRaisesRIR() {
        let out = SessionPlanner.apply([.capEffort(rir: 4)], to: [squat])
        #expect(out[0].rir == 4)

        let alreadyEasy = PlannedExercise(name: "Row", muscleGroup: .back, sets: 3, reps: 10,
                                          workingWeight: 135, increment: 5, rir: 5)
        let out2 = SessionPlanner.apply([.capEffort(rir: 3)], to: [alreadyEasy])
        #expect(out2[0].rir == 5, "a cap must not push someone closer to failure")
    }

    @Test("reduced load still lands on the lifter's own loadable grid")
    func loadStaysLoadable() {
        let out = SessionPlanner.apply([.reduceLoad(percent: 15)], to: [squat, bench])
        for proposed in out {
            let delta = proposed.planned.workingWeight - proposed.load
            #expect(abs(delta.truncatingRemainder(dividingBy: proposed.planned.increment)) < 1e-9)
        }
    }

    @Test("15% off a 315 squat with 10 lb jumps is 265")
    func loadArithmeticIsRight() {
        let out = SessionPlanner.apply([.reduceLoad(percent: 15)], to: [squat])
        #expect(out[0].load == 265)   // 47.25 rounds to 50
    }

    @Test("load never drops below a single increment")
    func loadNeverGoesToZero() {
        let light = PlannedExercise(name: "Rear delt", muscleGroup: .shoulders, sets: 3, reps: 15,
                                    workingWeight: 5, increment: 5, rir: 3)
        let out = SessionPlanner.apply([.reduceLoad(percent: 90)], to: [light])
        #expect(out[0].load >= 5)
    }

    @Test("deferring lower body leaves upper body alone")
    func deferHitsOnlyLowerBody() {
        let out = SessionPlanner.apply([.deferLowerBody], to: [squat, bench])
        #expect(out[0].isDeferred)
        #expect(!out[1].isDeferred)
    }

    @Test("a conditioning swap does not touch the lifting")
    func conditioningSwapLeavesLiftsAlone() {
        let out = SessionPlanner.apply([.swapConditioningToZone2], to: [squat])
        #expect(!out[0].changed)
    }

    @Test("several adjustments compose in one pass")
    func adjustmentsCompose() {
        let out = SessionPlanner.apply(
            [.reduceWorkingSets(percent: 20), .capEffort(rir: 4), .reduceLoad(percent: 15)],
            to: [squat])
        #expect(out[0].sets == 4)
        #expect(out[0].rir == 4)
        #expect(out[0].load == 265)
        #expect(out[0].changed)
    }

    @Test("the original plan is still readable next to the proposal")
    func originalSurvives() {
        let out = SessionPlanner.apply([.reduceLoad(percent: 15)], to: [squat])
        #expect(out[0].planned == squat, "the user's own plan must not be overwritten")
    }
}
