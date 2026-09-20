import Testing
@testable import ReadinessCore

private func set(_ load: Double, _ reps: Int, rir: Int = 2,
                 _ muscle: MuscleGroup = .quads, warmup: Bool = false) -> LiftSet {
    LiftSet(load: load, reps: reps, rir: rir, muscleGroup: muscle, isWarmup: warmup)
}

@Suite("Strength load features")
struct StrainEngineTests {

    @Test("volume load is weight times reps, summed")
    func volumeLoadSums() {
        let load = StrainEngine.sessionLoad(sets: [set(100, 5), set(100, 5)], sessionRPE: 7)
        #expect(load.volumeLoad == 1000)
    }

    @Test("warm-up sets are not training volume")
    func warmupsExcluded() {
        let load = StrainEngine.sessionLoad(
            sets: [set(60, 5, warmup: true), set(100, 5)], sessionRPE: 7)
        #expect(load.volumeLoad == 500)
    }

    @Test("a hard set is one taken within three reps of failure")
    func hardSetsCounted() {
        let load = StrainEngine.sessionLoad(
            sets: [set(100, 5, rir: 1), set(100, 5, rir: 3), set(100, 5, rir: 6)],
            sessionRPE: 8)
        #expect(load.hardSetsByMuscle[.quads] == 2)
    }

    @Test("hard sets are counted per muscle group, because fatigue is local")
    func hardSetsSplitByMuscle() {
        let load = StrainEngine.sessionLoad(
            sets: [set(100, 5, rir: 1, .quads), set(60, 8, rir: 2, .chest), set(60, 8, rir: 2, .chest)],
            sessionRPE: 8)
        #expect(load.hardSetsByMuscle[.quads] == 1)
        #expect(load.hardSetsByMuscle[.chest] == 2)
    }

    @Test("a warm-up is never a hard set, however close to failure it is recorded")
    func warmupIsNeverHard() {
        let load = StrainEngine.sessionLoad(sets: [set(60, 5, rir: 0, warmup: true)], sessionRPE: 5)
        #expect(load.hardSetsByMuscle.isEmpty)
    }

    @Test("proximity to failure is the share of working sets taken hard")
    func closeToFailureShare() {
        let load = StrainEngine.sessionLoad(
            sets: [set(100, 5, rir: 1), set(100, 5, rir: 8)], sessionRPE: 7)
        #expect(abs(load.closeToFailureShare - 0.5) < 1e-9)
    }

    @Test("an empty session has no load and does not divide by zero")
    func emptySessionIsSafe() {
        let load = StrainEngine.sessionLoad(sets: [], sessionRPE: 0)
        #expect(load.volumeLoad == 0)
        #expect(load.closeToFailureShare == 0)
    }
}

@Suite("Acute against chronic load")
struct ACWRTests {

    @Test("steady training sits at about 1.0")
    func steadyTrainingIsOne() {
        let acwr = StrainEngine.acwr(daily: Array(repeating: 1000.0, count: 28), observedDays: 28)
        #expect(abs((acwr ?? 0) - 1.0) < 1e-9)
    }

    @Test("a hard week against an easy month reads as a spike")
    func spikeIsDetected() {
        let daily = Array(repeating: 500.0, count: 21) + Array(repeating: 1500.0, count: 7)
        let acwr = StrainEngine.acwr(daily: daily, observedDays: daily.count)
        #expect((acwr ?? 0) > 1.5)
    }

    @Test("backing off reads below 1.0")
    func taperIsDetected() {
        let daily = Array(repeating: 1000.0, count: 21) + Array(repeating: 300.0, count: 7)
        #expect((StrainEngine.acwr(daily: daily, observedDays: daily.count) ?? 9) < 1.0)
    }

    @Test("too little history to compare returns nothing rather than a guess")
    func shortHistoryReturnsNil() {
        #expect(StrainEngine.acwr(daily: Array(repeating: 1000.0, count: 10), observedDays: 10) == nil)
    }

    @Test("one session against a month of rest is not a load spike")
    func singleSessionIsNotASpike() {
        // 27 rest days and one session gives a mathematically enormous ratio and a
        // meaningless one. Reporting it would cap a good morning for no reason.
        let daily = Array(repeating: 0.0, count: 27) + [1125.0]
        #expect(StrainEngine.acwr(daily: daily, observedDays: daily.count) == nil)
    }

    @Test("enough training days in the window produce a ratio")
    func enoughTrainingDaysProducesARatio() {
        var daily = Array(repeating: 0.0, count: 28)
        for index in [2, 6, 10, 15, 20, 24, 27] { daily[index] = 1000 }
        #expect(StrainEngine.acwr(daily: daily, observedDays: daily.count) != nil)
    }

    @Test("a month of rest cannot divide by zero")
    func zeroChronicIsSafe() {
        let acwr = StrainEngine.acwr(daily: Array(repeating: 0.0, count: 28), observedDays: 28)
        #expect(acwr == nil || (acwr ?? 0).isFinite)
    }
}

@Suite("Session novelty")
struct NoveltyTests {

    @Test("a session like the recent norm is not novel")
    func routineSessionIsNotNovel() {
        let n = StrainEngine.novelty(todayVolume: 1000, recentVolumes: Array(repeating: 1000, count: 10))
        #expect(n < 0.1)
    }

    @Test("a big jump in volume is novel")
    func jumpIsNovel() {
        let n = StrainEngine.novelty(todayVolume: 2500, recentVolumes: Array(repeating: 1000, count: 10))
        #expect(n > 0.5)
    }

    @Test("an easier day is not flagged as novel load")
    func lighterDayIsNotNovel() {
        let n = StrainEngine.novelty(todayVolume: 400, recentVolumes: Array(repeating: 1000, count: 10))
        #expect(n == 0)
    }

    @Test("novelty is bounded so one outlier cannot dominate")
    func noveltyIsBounded() {
        let n = StrainEngine.novelty(todayVolume: 100_000, recentVolumes: Array(repeating: 1000, count: 10))
        #expect(n <= 1.0)
    }

    @Test("no history means nothing to be novel against")
    func noHistoryIsZero() {
        #expect(StrainEngine.novelty(todayVolume: 1000, recentVolumes: []) == 0)
    }
}
