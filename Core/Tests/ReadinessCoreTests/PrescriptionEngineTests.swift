import Testing
@testable import ReadinessCore

private let squat = Lift(name: "Back squat", workingWeight: 315, increment: 10, repTarget: 5, rirTarget: 2)
private let press = Lift(name: "Overhead press", workingWeight: 135, increment: 5, repTarget: 5, rirTarget: 2)

@Suite("Prescription: percent in, loadable weight out")
struct PrescriptionMappingTests {

    @Test("a day at baseline runs the program as written")
    func baselineRunsAsWritten() {
        let p = PrescriptionEngine.prescribe(lift: squat, state: .atBaseline, multiDayTrendPresent: true)
        #expect(p.prescribedLoad == squat.workingWeight)
        #expect(abs(p.appliedPercent) < 1e-9)
    }

    @Test("a below-baseline day prescribes less weight")
    func belowBaselineCutsLoad() {
        let p = PrescriptionEngine.prescribe(lift: squat, state: .belowBaseline, multiDayTrendPresent: true)
        #expect(p.prescribedLoad < squat.workingWeight)
    }

    @Test("an above-baseline day prescribes more weight")
    func aboveBaselineAddsLoad() {
        let p = PrescriptionEngine.prescribe(lift: squat, state: .aboveBaseline, multiDayTrendPresent: true)
        #expect(p.prescribedLoad > squat.workingWeight)
    }

    @Test("a well-below-baseline day cuts harder than a below-baseline day")
    func wellBelowCutsHarder() {
        let mild = PrescriptionEngine.prescribe(lift: squat, state: .belowBaseline, multiDayTrendPresent: true)
        let severe = PrescriptionEngine.prescribe(lift: squat, state: .wellBelowBaseline, multiDayTrendPresent: true)
        #expect(severe.prescribedLoad < mild.prescribedLoad)
    }

    @Test("every prescribed load sits on the lifter's own loadable grid")
    func loadsAreAlwaysLoadable() {
        // The grid is workingWeight +/- n*increment. A squat at 315 with 10 lb jumps
        // moves to 305 or 325: never to 310. So the *delta* is what must divide.
        for state in ReadinessState.allCases {
            for lift in [squat, press] {
                let p = PrescriptionEngine.prescribe(lift: lift, state: state, multiDayTrendPresent: true)
                let delta = p.prescribedLoad - lift.workingWeight
                let remainder = delta.truncatingRemainder(dividingBy: lift.increment)
                #expect(abs(remainder) < 1e-9,
                        "\(lift.name) at \(state) moved \(delta), not a multiple of \(lift.increment)")
            }
        }
    }

    @Test("the reported percent is what was actually applied after rounding, not the intended percent")
    func appliedPercentIsPostRounding() {
        let p = PrescriptionEngine.prescribe(lift: squat, state: .belowBaseline, multiDayTrendPresent: true)
        let recomputed = (p.prescribedLoad - squat.workingWeight) / squat.workingWeight
        #expect(abs(p.appliedPercent - recomputed) < 1e-9)
    }

    @Test("rep and RIR targets pass through untouched")
    func targetsCarryThrough() {
        let p = PrescriptionEngine.prescribe(lift: squat, state: .belowBaseline, multiDayTrendPresent: true)
        #expect(p.repTarget == squat.repTarget)
        #expect(p.rirTarget == squat.rirTarget)
        #expect(p.lift == squat)
    }
}

@Suite("Prescription bounds: spec 3.4")
struct PrescriptionBoundsTests {

    @Test("no state's base adjustment escapes the floor and ceiling")
    func basePercentsAreWithinBounds() {
        for state in ReadinessState.allCases {
            let pct = PrescriptionEngine.basePercent(for: state)
            #expect(pct >= PrescriptionEngine.floorPercent, "\(state) fell through the floor")
            #expect(pct <= PrescriptionEngine.ceilingPercent, "\(state) broke the ceiling")
        }
    }

    @Test("without a multi-day trend the change is capped at a single increment")
    func singleSessionCappedAtOneIncrement() {
        let p = PrescriptionEngine.prescribe(lift: squat, state: .wellBelowBaseline,
                                             multiDayTrendPresent: false)
        let delta = abs(p.prescribedLoad - squat.workingWeight)
        #expect(delta <= squat.increment,
                "moved \(delta) lb on one day's signal with no trend behind it")
    }

    @Test("with a multi-day trend a severe day may move more than one increment")
    func trendUnlocksLargerMove() {
        let p = PrescriptionEngine.prescribe(lift: squat, state: .wellBelowBaseline,
                                             multiDayTrendPresent: true)
        let delta = abs(p.prescribedLoad - squat.workingWeight)
        #expect(delta > squat.increment)
    }

    @Test("the cap applies to upward moves too")
    func upwardMovesAlsoCapped() {
        let p = PrescriptionEngine.prescribe(lift: squat, state: .aboveBaseline,
                                             multiDayTrendPresent: false)
        let delta = abs(p.prescribedLoad - squat.workingWeight)
        #expect(delta <= squat.increment)
    }

    @Test("no prescription ever drops below the floor percentage")
    func neverBelowFloor() {
        for state in ReadinessState.allCases {
            let p = PrescriptionEngine.prescribe(lift: squat, state: state, multiDayTrendPresent: true)
            #expect(p.appliedPercent >= PrescriptionEngine.floorPercent - 0.02,
                    "\(state) prescribed \(p.appliedPercent)")
        }
    }
}

@Suite("Plate math")
struct PlateMathTests {

    @Test("an exact multiple is left alone")
    func exactMultipleUnchanged() {
        #expect(PlateMath.round(315, toIncrement: 5) == 315)
    }

    @Test("rounds to the nearest increment")
    func roundsToNearest() {
        #expect(PlateMath.round(292.875, toIncrement: 5) == 295)
        #expect(PlateMath.round(291.0, toIncrement: 5) == 290)
    }

    @Test("a zero increment is a guard, not a divide by zero")
    func zeroIncrementIsSafe() {
        #expect(PlateMath.round(292.875, toIncrement: 0) == 292.875)
    }

    @Test("never returns a negative load")
    func neverNegative() {
        #expect(PlateMath.round(-20, toIncrement: 5) >= 0)
    }
}
