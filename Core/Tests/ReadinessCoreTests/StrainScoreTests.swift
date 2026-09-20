import Foundation
import Testing
@testable import ReadinessCore

// Strain on Banister TRIMP, mapped to 0...21.
// See docs/superpowers/specs/2026-09-19-signal-scores-design.md.

private func minutes(_ count: Double, at heartRate: Double) -> [HeartRateSample] {
    [HeartRateSample(start: Date(), minutes: count, beatsPerMinute: heartRate)]
}

/// The heart rate that sits `fraction` of the way up the reserve, for a 30-year-old with
/// a resting rate of 50. Tanaka puts their maximum at 187.
private func heartRate(atReserve fraction: Double, resting: Double = 50,
                       maximum: Double = 187) -> Double {
    resting + fraction * (maximum - resting)
}

/// Sixteen waking hours at an unremarkable desk-job heart rate, which is what the
/// engine actually gets handed every day and what none of the first tests supplied.
private func wakingDay(at heartRate: Double = 70) -> [HeartRateSample] {
    (0..<192).map {
        HeartRateSample(start: Date().addingTimeInterval(Double($0) * 300),
                        minutes: 5, beatsPerMinute: heartRate)
    }
}

private func input(_ samples: [HeartRateSample] = [], hardSets: Int = 0,
                   resting: Double? = 50, age: Int? = 30,
                   sex: HealthProfile.BiologicalSex? = .male,
                   fallback: DailyStrainResult? = nil) -> StrainInput {
    StrainInput(samples: samples, restingHeartRate: resting, ageYears: age,
                biologicalSex: sex, hardSets: hardSets, fallback: fallback)
}

@Suite("Maximum heart rate")
struct MaxHeartRateTests {

    /// Tanaka, not 220 minus age. The older formula overestimates for the young and
    /// underestimates for the old, and every heart rate reserve below depends on it.
    @Test("Tanaka, to the beat", arguments: [(20, 194.0), (30, 187.0), (50, 173.0)])
    func tanaka(age: Int, expected: Double) {
        #expect(abs(StrainScore.maximumHeartRate(ageYears: age) - expected) < 0.5)
    }

    @Test("an unknown age falls back rather than guessing a birthday")
    func unknownAge() {
        #expect(StrainScore.maximumHeartRate(ageYears: nil) == StrainScore.assumedMaximumHeartRate)
    }

    /// Somebody who has actually been seen above their predicted maximum has a higher
    /// maximum. The formula is a population average, and the measurement is the person.
    @Test("an observed maximum beats the formula when it is higher")
    func observedMaximumWins() {
        #expect(StrainScore.maximumHeartRate(ageYears: 30, observed: 199) == 199)
        #expect(StrainScore.maximumHeartRate(ageYears: 30, observed: 150) == 187)
    }
}

@Suite("Banister TRIMP")
struct TrimpTests {

    /// The worked example in the spec, and the one number that proves the formula was
    /// transcribed rather than remembered.
    @Test("an hour at three quarters of reserve is 121.6 for a man")
    func workedExample() {
        let load = StrainScore.trimp(minutes: 60, heartRate: heartRate(atReserve: 0.75),
                                     resting: 50, maximum: 187, sex: .male)
        #expect(abs(load - 121.6) < 0.1, "got \(load)")
    }

    /// Published ceilings. The coefficient is 0.64 for both sexes and only the exponent
    /// differs, which is the part that is easy to get backwards.
    @Test("the per-minute ceiling matches the published values")
    func ceilings() {
        let male = StrainScore.trimp(minutes: 1, heartRate: 187, resting: 50,
                                     maximum: 187, sex: .male)
        let female = StrainScore.trimp(minutes: 1, heartRate: 187, resting: 50,
                                       maximum: 187, sex: .female)
        #expect(abs(male - 4.365) < 0.01, "got \(male)")
        #expect(abs(female - 3.400) < 0.01, "got \(female)")
    }

    @Test("an unknown sex sits between the two rather than picking one")
    func unknownSex() {
        let unknown = StrainScore.trimp(minutes: 1, heartRate: 187, resting: 50,
                                        maximum: 187, sex: nil)
        #expect(unknown > 3.400 && unknown < 4.365)
    }

    /// Higher intensity costs disproportionately more, which is the entire reason for
    /// the exponential and the reason duration alone cannot measure load.
    @Test("intensity is worth more than duration")
    func intensityBeatsDuration() {
        let long = StrainScore.trimp(minutes: 60, heartRate: heartRate(atReserve: 0.4),
                                     resting: 50, maximum: 187, sex: .male)
        let short = StrainScore.trimp(minutes: 30, heartRate: heartRate(atReserve: 0.8),
                                      resting: 50, maximum: 187, sex: .male)
        #expect(short > long, "30 hard minutes (\(short)) should beat 60 easy (\(long))")
    }

    @Test("resting and below contributes nothing rather than going negative")
    func belowResting() {
        #expect(StrainScore.trimp(minutes: 60, heartRate: 44, resting: 50,
                                  maximum: 187, sex: .male) == 0)
    }

    @Test("above maximum is clamped rather than extrapolated")
    func aboveMaximum() {
        let atMax = StrainScore.trimp(minutes: 1, heartRate: 187, resting: 50,
                                      maximum: 187, sex: .male)
        let beyond = StrainScore.trimp(minutes: 1, heartRate: 210, resting: 50,
                                       maximum: 187, sex: .male)
        #expect(beyond == atMax)
    }
}

@Suite("The 0 to 21 map")
struct StrainCurveTests {

    /// Re-anchored when the curve moved from 40/400 to 20/650. The old pair spent six
    /// of the twenty-one points below anything anybody would call training, and put a
    /// three-hour easy ride at 19.4 — "all out" — while a genuinely epic day clamped at
    /// the same 21 as a hard hour and a half.
    @Test("the anchors sit where the spec says", arguments: [
        (0.0, 0.000), (20.0, 19.739), (40.0, 31.286), (100.0, 51.025),
        (141.6, 59.501), (300.0, 78.956), (650.0, 100.000),
    ])
    func anchors(load: Double, expected: Double) {
        #expect(abs(StrainScore.strain(load: load) - expected) < 0.02,
                "load \(load) gave \(StrainScore.strain(load: load))")
    }

    @Test("the scale stops at its top rather than running off the end")
    func clamped() {
        #expect(StrainScore.strain(load: 2000) == 100)
        #expect(StrainScore.strain(load: -5) == 0)
    }

    /// Non-linear on purpose: it costs far more to go from 16 to 17 than from 4 to 5.
    @Test("each point costs more than the one before it")
    func logarithmic() {
        let early = StrainScore.load(strain: 25) - StrainScore.load(strain: 20)
        let late = StrainScore.load(strain: 85) - StrainScore.load(strain: 80)
        #expect(late > early * 3)
    }

    @Test("bands follow the scale", arguments: [
        (0.0, ScoreBand.light), (49.9, .light), (50.0, .moderate), (69.9, .moderate),
        (70.0, .hard), (84.9, .hard), (85.0, .allOut), (100.0, .allOut),
    ])
    func bands(value: Double, expected: ScoreBand) {
        #expect(ScoreBand.strain(value: value) == expected)
    }
}

@Suite("Muscular load")
struct MuscularLoadTests {

    /// Lifting is invisible to a heart rate measure — a heavy triple barely moves the
    /// average — so hard sets carry their own load, and Insights shows both.
    @Test("twenty hard sets is worth a hundred")
    func hardSets() {
        #expect(StrainScore.muscularLoad(hardSets: 20) == 100)
    }

    /// At the old 2.0 a set was worth half a minute of jogging and lifting alone could
    /// not leave the bottom band until about forty-three sets, which no lifter would
    /// accept. Twenty hard sets is a real session and should read as one.
    @Test("a real lifting session reaches the middle of the scale")
    func liftingReachesModerate() throws {
        let value = try #require(StrainScore.of(input(hardSets: 20)).value)
        #expect(value >= 50, "20 hard sets read as \(value)")
        #expect(ScoreBand.strain(value: value) == .moderate)
    }

    @Test("a lifting session with no cardiac trace still produces strain")
    func liftingAlone() throws {
        let result = StrainScore.of(input(hardSets: 20))
        let value = try #require(result.value)
        #expect(value > 25, "20 hard sets read as \(value)")
    }

    @Test("both loads are reported separately")
    func bothReported() {
        let result = StrainScore.of(input(minutes(45, at: heartRate(atReserve: 0.6)),
                                          hardSets: 12))
        let ids = Set(result.contributors.map(\.id))
        #expect(ids.contains(StrainScore.muscularContributorID))
        #expect(ids.contains { $0.hasPrefix("zone") })
    }
}

@Suite("Strain contributions")
struct StrainContributionTests {

    @Test("zone minutes add up to the minutes recorded")
    func zoneMinutes() {
        let samples = minutes(30, at: heartRate(atReserve: 0.2))
            + minutes(20, at: heartRate(atReserve: 0.65))
            + minutes(10, at: heartRate(atReserve: 0.85))
        let result = StrainScore.of(input(samples))
        let reported = result.contributors
            .filter { $0.id.hasPrefix("zone") }
            .reduce(0) { $0 + ($1.value ?? 0) }
        #expect(abs(reported - 60) < 0.01, "reported \(reported) minutes of 60")
    }

    /// Strain's neutral point is zero, so the rows have to sum to the number itself.
    @Test("contributor magnitudes sum to the strain")
    func magnitudesSum() throws {
        let result = StrainScore.of(input(minutes(50, at: heartRate(atReserve: 0.7)),
                                          hardSets: 8))
        let value = try #require(result.value)
        let summed = result.contributors.reduce(0) { $0 + $1.magnitude }
        #expect(abs(summed - value) < 0.01, "rows sum to \(summed), strain is \(value)")
    }

    @Test("the hardest zone leads the breakdown when it dominates the load")
    func rankedByLoad() {
        let samples = minutes(120, at: heartRate(atReserve: 0.1))
            + minutes(25, at: heartRate(atReserve: 0.9))
        let result = StrainScore.of(input(samples))
        #expect(result.contributors.first?.id == "zone5")
    }

    @Test("a zone nobody entered is not listed")
    func emptyZonesOmitted() {
        let result = StrainScore.of(input(minutes(30, at: heartRate(atReserve: 0.85))))
        #expect(!result.contributors.contains { $0.id == "zone1" })
    }
}

@Suite("Strain coverage")
struct StrainCoverageTests {

    /// The common case for anybody without a watch. It must degrade to the activity
    /// percentile that shipped before this, not to an empty ring.
    @Test("no heart rate falls back to the recorded activity comparison")
    func fallsBackToActivity() throws {
        let activity = DailyStrainResult(percent: 75, metric: .activeEnergy, value: 600,
                                         baselineDays: 14, coverage: .relativeToHistory)
        let result = StrainScore.of(input(fallback: activity))
        #expect(result.value != nil)
        #expect(result.coverage == .partial)
        #expect(result.missing.contains { $0.localizedCaseInsensitiveContains("heart rate") })
        #expect(try #require(result.value) > 0)
    }

    @Test("no heart rate and no activity is no score rather than a zero")
    func nothingAtAll() {
        let result = StrainScore.of(input())
        #expect(result.value == nil)
        #expect(result.coverage == .unavailable)
    }

    /// A day with a watch on and nothing done is a real zero, and has to be
    /// distinguishable from a day the watch was in a drawer.
    @Test("a recorded quiet day is a real zero")
    func quietDay() {
        let result = StrainScore.of(input(minutes(600, at: 48)))
        #expect(result.value == 0)
        #expect(result.coverage != .unavailable)
    }

    @Test("a missing age is named and the score still stands")
    func missingAge() {
        let result = StrainScore.of(input(minutes(40, at: 150), age: nil))
        #expect(result.value != nil)
        #expect(result.coverage == .partial)
        #expect(result.missing.contains { $0.localizedCaseInsensitiveContains("age") })
    }

    @Test("a missing resting heart rate is named and the score still stands")
    func missingResting() {
        let result = StrainScore.of(input(minutes(40, at: 150), resting: nil))
        #expect(result.value != nil)
        #expect(result.coverage == .partial)
    }

    @Test("everything present reads as full coverage")
    func fullCoverage() {
        let result = StrainScore.of(input(wakingDay() + minutes(40, at: 150), hardSets: 6))
        #expect(result.coverage == .full)
        #expect(result.missing.isEmpty)
    }

    /// A watch worn for four hours produces a real number out of a fifth of a day and
    /// used to claim it had everything it wanted. Either the session was caught and
    /// nothing around it was, or the session was missed and a hard day reads as a rest
    /// day — silently, in both directions.
    /// Was one 240-minute sample, which is not what a sparse day looks like — under the
    /// span-and-density check that reads as four hours fully covered, which it is.
    /// A real thin trace is a few readings spread across the day.
    @Test("a barely worn watch says so")
    func shortWearTime() {
        let sparse = (0..<4).map {
            HeartRateSample(start: Date().addingTimeInterval(Double($0) * 3600),
                            minutes: 5, beatsPerMinute: 120)
        }
        let result = StrainScore.of(input(sparse))
        #expect(result.coverage == .partial)
        #expect(result.missing.contains { $0.localizedCaseInsensitiveContains("part of the day") })
    }

    /// The other half: a span alone said nothing about whether the day was described.
    @Test("two readings twelve hours apart are not a record of a day")
    func spanWithoutDensity() {
        let bookends = [
            HeartRateSample(start: Date(), minutes: 5, beatsPerMinute: 70),
            HeartRateSample(start: Date().addingTimeInterval(12 * 3600),
                            minutes: 5, beatsPerMinute: 70),
        ]
        #expect(StrainScore.of(input(bookends)).coverage == .partial)
    }

    @Test("nonsense samples are ignored rather than poisoning the total")
    func rubbishSamples() {
        let samples = [
            HeartRateSample(start: Date(), minutes: .nan, beatsPerMinute: 120),
            HeartRateSample(start: Date(), minutes: 10, beatsPerMinute: .infinity),
            HeartRateSample(start: Date(), minutes: -5, beatsPerMinute: 120),
            HeartRateSample(start: Date(), minutes: 30, beatsPerMinute: 150),
        ]
        let result = StrainScore.of(input(samples))
        let clean = StrainScore.of(input(minutes(30, at: 150)))
        #expect(result.value == clean.value)
    }
}

@Suite("A day of doing nothing")
struct SedentaryDayTests {

    /// The bug the whole recalibration exists for, and the one every earlier test
    /// missed by feeding the engine half-hour toy traces instead of a day.
    ///
    /// Sixteen waking hours at 70 bpm is 87 TRIMP. On the old curve that was a strain
    /// of 10 out of 21 — "moderate" — for somebody who did nothing whatsoever, rising
    /// to "hard" at 80 bpm. A stressed or caffeinated person who never exercises read
    /// as having trained, every single day, forever.
    @Test("a desk day with no exercise stays in the bottom band", arguments: [68.0, 70.0, 75.0, 80.0])
    func sedentaryStaysLight(restingAverage: Double) throws {
        let result = StrainScore.of(input(wakingDay(at: restingAverage)))
        let value = try #require(result.value)
        #expect(value < 28, "doing nothing at \(restingAverage) bpm read as \(value)")
        #expect(result.band == .light)
    }

    /// Fifteen hours of sitting used to outweigh a 45-minute run, so on a day somebody
    /// ran, the top row of the breakdown was sitting down.
    @Test("a run outranks the sitting around it")
    func exerciseLeadsTheBreakdown() {
        let result = StrainScore.of(input(wakingDay() + minutes(45, at: 145)))
        #expect(result.contributors.first?.id != "zone0",
                "the day's leading contributor was \(result.contributors.first?.title ?? "nothing")")
    }

    @Test("a run still moves the number")
    func exerciseMoves() throws {
        let idle = try #require(StrainScore.of(input(wakingDay())).value)
        let ran = try #require(StrainScore.of(input(wakingDay() + minutes(45, at: 145))).value)
        #expect(ran - idle > 18, "a 45 minute run moved it \(ran - idle)")
    }

    /// Capping what being awake can cost must not cap what it can show.
    @Test("the capped minutes are still reported truthfully")
    func minutesSurviveTheCap() throws {
        let result = StrainScore.of(input(wakingDay()))
        let everyday = try #require(result.contributors.first { $0.id == "zone0" })
        #expect(everyday.value == 960)
    }

    /// The ceiling has to be out of reach of a normal hard day, or the top of the scale
    /// is decoration. A three-hour easy ride used to read 19.4 — all out.
    @Test("a long easy ride is hard, not all out")
    func longRideIsNotAllOut() throws {
        let ride = wakingDay() + minutes(180, at: 140)
        let value = try #require(StrainScore.of(input(ride)).value)
        #expect(value >= 70 && value < 85, "a 3 hour easy ride read as \(value)")
    }
}

@Suite("Acute-to-chronic needs a real chronic window")
struct ACWRGuardTests {

    /// One volume per day, most recent last.
    private func days(sessionsOn offsets: [Int]) -> [Double] {
        (0..<StrainEngine.chronicDays).map { index in
            let offset = StrainEngine.chronicDays - 1 - index
            return offsets.contains(offset) ? 1000 : 0
        }
    }

    /// The guard's own comment says one session against twenty-seven rest days is
    /// arithmetically a 4.0 spike and tells you nothing. Three sessions crammed into the
    /// most recent week against twenty-one empty ones is the same 4.0, and it capped
    /// every good morning of a new logger's first fortnight.
    @Test("a first week of logging is not a spike")
    func firstWeekIsNotASpike() {
        #expect(StrainEngine.acwr(daily: days(sessionsOn: [1, 3, 5])) == nil)
        #expect(StrainEngine.acwr(daily: days(sessionsOn: [0, 2, 4, 6])) == nil)
    }

    @Test("neither is a first week back after a lay-off")
    func returningIsNotASpike() {
        #expect(StrainEngine.acwr(daily: days(sessionsOn: [1, 3, 5])) == nil)
    }

    /// But a genuine spike, on top of a real habit, still has to register.
    @Test("a real spike on a real history still fires")
    func realSpikeFires() throws {
        let habit = Array(stride(from: 8, through: 27, by: 3))
        let ratio = try #require(StrainEngine.acwr(daily: days(sessionsOn: habit + [0, 1, 2, 3, 4, 5, 6])))
        #expect(ratio > ReadinessEngine.acwrGate, "a genuine spike read as \(ratio)")
    }

    @Test("and a steady habit does not")
    func steadyIsClear() throws {
        let steady = Array(stride(from: 0, through: 27, by: 3))
        let ratio = try #require(StrainEngine.acwr(daily: days(sessionsOn: steady)))
        #expect(ratio <= ReadinessEngine.acwrGate, "a steady habit read as \(ratio)")
    }
}
