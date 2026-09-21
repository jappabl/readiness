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
    // Read after the last reading, not at the moment the fixture was built. These
    // helpers start their samples at `Date()` and run forwards, so the default `readAt`
    // sat before every one of them: a day whose trace is entirely in its own future,
    // which no window can describe.
    let last = samples.map { $0.start.addingTimeInterval($0.minutes * 60) }.max()
    return StrainInput(samples: samples, restingHeartRate: resting, ageYears: age,
                       biologicalSex: sex, hardSets: hardSets,
                       readAt: last.map { Swift.max($0, Date()) } ?? Date(),
                       fallback: fallback)
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
    /// three-hour easy ride at 19.4 ("all out") while a genuinely epic day clamped at
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

    /// Lifting is invisible to a heart rate measure: a heavy triple barely moves the
    /// average, so hard sets carry their own load, and Insights shows both.
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
    /// day: silently, in both directions.
    /// Was one 240-minute sample, which is not what a sparse day looks like: under the
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
    /// of 10 out of 21 ("moderate") for somebody who did nothing whatsoever, rising
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
    /// is decoration. A three-hour easy ride used to read 19.4, all out.
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

    /// Three sessions crammed into the most recent week against twenty-one empty ones is
    /// arithmetically a 4.0 spike and tells you nothing, but only because those twenty-
    /// one days predate the record. The fix is the denominator, not a spread guard: the
    /// chronic mean divides by how long the app has been watching.
    @Test("a first week of logging is not a spike")
    func firstWeekIsNotASpike() throws {
        let ratio = try #require(StrainEngine.acwr(daily: days(sessionsOn: [1, 3, 5]),
                                                   observedDays: 7))
        #expect(ratio <= ReadinessEngine.acwrGate, "a first week read as \(ratio)")
    }

    /// And the case that must NOT be suppressed, which a spread guard did suppress:
    /// months of training, three weeks off, then four hard days back. That is what this
    /// ratio exists to catch.
    @Test("coming back hard after a lay-off is a spike")
    func returningIsASpike() throws {
        let back = days(sessionsOn: [0, 1, 2, 3])
        let ratio = try #require(StrainEngine.acwr(daily: back, observedDays: 150))
        #expect(ratio > ReadinessEngine.acwrGate, "four hard days after three weeks off read as \(ratio)")
    }

    /// But a genuine spike, on top of a real habit, still has to register.
    @Test("a real spike on a real history still fires")
    func realSpikeFires() throws {
        let habit = Array(stride(from: 8, through: 27, by: 3))
        let ratio = try #require(StrainEngine.acwr(
            daily: days(sessionsOn: habit + [0, 1, 2, 3, 4, 5, 6]), observedDays: 150))
        #expect(ratio > ReadinessEngine.acwrGate, "a genuine spike read as \(ratio)")
    }

    @Test("and a steady habit does not")
    func steadyIsClear() throws {
        let steady = Array(stride(from: 0, through: 27, by: 3))
        let ratio = try #require(StrainEngine.acwr(daily: days(sessionsOn: steady),
                                                   observedDays: 150))
        #expect(ratio <= ReadinessEngine.acwrGate, "a steady habit read as \(ratio)")
    }
}

@Suite("The wear check needs a clock")
struct WearTimeClockTests {

    /// Woke at seven, whatever time the watch went on.
    private func day(from startHour: Int, hours: Double, bpm: Double = 90,
                     readAtHour: Int, wokeAtHour: Int = 7) -> StrainInput {
        let midnight = Calendar.current.startOfDay(for: Date())
        let start = midnight.addingTimeInterval(Double(startHour) * 3600)
        let samples = (0..<Int(hours * 12)).map {
            HeartRateSample(start: start.addingTimeInterval(Double($0) * 300),
                            minutes: 5, beatsPerMinute: bpm)
        }
        // The night that ended at `wokeAtHour`, which is what says when the day began.
        let woke = midnight.addingTimeInterval(Double(wokeAtHour) * 3600)
        return StrainInput(samples: samples, restingHeartRate: 55, ageYears: 30,
                           biologicalSex: .male, hardSets: 0,
                           readAt: midnight.addingTimeInterval(Double(readAtHour) * 3600),
                           asleepPeriods: [DateInterval(
                               start: woke.addingTimeInterval(-8 * 3600), end: woke)])
    }

    /// `elapsed` used to be derived from `span`, which made the test
    /// `span < min(720, span)`: false for every trace ever recorded. Only density fired,
    /// so a watch worn four hours reported a complete day and an evening session that
    /// was never recorded showed up as nothing at all.
    @Test("a watch worn for four hours of a full day says so")
    func shortWearFlagged() {
        let result = StrainScore.of(day(from: 9, hours: 4, readAtHour: 23))
        #expect(result.coverage == .partial)
        #expect(result.missing.contains { $0.localizedCaseInsensitiveContains("part of the day") })
    }

    @Test("so does a trace that is only the session")
    func sessionOnlyFlagged() {
        #expect(StrainScore.of(day(from: 19, hours: 1, readAtHour: 23)).coverage == .partial)
    }

    /// And round 3's complaint stays fixed: a normally worn day must not be flagged
    /// merely because the day is not over yet.
    @Test("a normally worn day is never flagged, whatever the hour", arguments: [9, 12, 15, 18, 23])
    func normalWearIsSilent(readAtHour: Int) {
        let worn = Double(readAtHour - 7)
        let result = StrainScore.of(day(from: 7, hours: worn, readAtHour: readAtHour))
        #expect(result.coverage == .full, "flagged at \(readAtHour):00 after \(worn) h worn")
    }

    /// The mirror of the case above, and the one my first fix could not catch. Measuring
    /// elapsed from the first sample meant a late-worn watch had a span equal to the
    /// elapsed time, so the test was `span < span × share`: false however late it went
    /// on. Fifty-six minutes of a sixteen-hour day reported a complete record.
    /// 15:00 used to be excluded, because eight hours of a sixteen-hour waking day sat
    /// exactly on the old share threshold. Measuring the leading gap instead has no such
    /// boundary, so the case is an ordinary one now.
    @Test("a watch put on late says so", arguments: [12, 15, 16, 17, 19, 21, 22])
    func lateWearFlagged(onAtHour: Int) {
        let result = StrainScore.of(day(from: onAtHour, hours: Double(23 - onAtHour),
                                        readAtHour: 23))
        #expect(result.coverage == .partial,
                "watch on at \(onAtHour):00 of a day that started at 07:00 read as complete")
    }

    /// A watch on the charger until nine is a two-hour hole in the record, and this test
    /// used to assert it was nothing to mention. That expectation was written when the
    /// only available tests were shares of the day, and it does not survive the question
    /// being asked properly: a two-hour hole and a ninety-minute hole are the same event,
    /// and a session fits in either. The app under-reporting a hard morning is the
    /// expensive error; a line saying the record covers fourteen hours is the cheap one.
    @Test("a morning on the charger is a hole like any other")
    func morningChargeIsReported() {
        #expect(StrainScore.of(day(from: 9, hours: 14, readAtHour: 23)).coverage == .partial)
    }

    /// The charge that genuinely is nothing: back on the wrist inside half an hour.
    @Test("a brief charge is not a missing day")
    func briefChargeIsSilent() {
        let midnight = Calendar.current.startOfDay(for: Date())
        let samples = (0..<186).map {
            HeartRateSample(start: midnight.addingTimeInterval(7.5 * 3600 + Double($0) * 300),
                            minutes: 5, beatsPerMinute: 80)
        }
        let result = StrainScore.of(StrainInput(
            samples: samples, restingHeartRate: 55, ageYears: 30, biologicalSex: .male,
            hardSets: 0, readAt: midnight.addingTimeInterval(23 * 3600),
            asleepPeriods: [DateInterval(start: midnight.addingTimeInterval(-3600),
                                         end: midnight.addingTimeInterval(7 * 3600))]))
        #expect(result.coverage == .full, "a 30-minute charge was called a missing day")
    }
}

@Suite("Acute-to-chronic waits for a record")
struct ACWRObservedDaysTests {

    private func steady(sessionsPerWeek: Int, days: Int) -> [Double] {
        let spacing = 7 / sessionsPerWeek
        return (0..<StrainEngine.chronicDays).map { index in
            let offset = StrainEngine.chronicDays - 1 - index
            guard offset < days else { return 0 }
            return offset % spacing == 0 ? 5000 : 0
        }
    }

    /// The chronic mean divided by a fixed twenty-eight whether or not the app had been
    /// watching, so the window was padded with days that predate the record. A perfectly
    /// steady logger was told they had spiked on seven consecutive days around week two.
    @Test("a steady habit never spikes, however new the record is",
          arguments: [10, 12, 14, 16, 18, 21, 28])
    func steadyHabitNeverSpikes(days: Int) {
        let ratio = StrainEngine.acwr(daily: steady(sessionsPerWeek: 3, days: days),
                                      observedDays: days)
        if let ratio {
            #expect(ratio <= ReadinessEngine.acwrGate,
                    "day \(days) of a steady habit read as \(ratio)")
        }
    }

    @Test("twice a week is the same story")
    func twiceAWeek() {
        for days in [13, 16, 19, 28] {
            if let ratio = StrainEngine.acwr(daily: steady(sessionsPerWeek: 2, days: days),
                                            observedDays: days) {
                #expect(ratio <= ReadinessEngine.acwrGate, "day \(days) read as \(ratio)")
            }
        }
    }

    /// A genuine spike on a long record still has to fire.
    @Test("a real spike on a real record still fires")
    func realSpikeStillFires() throws {
        var daily = steady(sessionsPerWeek: 3, days: StrainEngine.chronicDays)
        for index in (daily.count - StrainEngine.acuteDays)..<daily.count { daily[index] = 5000 }
        let ratio = try #require(StrainEngine.acwr(daily: daily, observedDays: 200))
        #expect(ratio > ReadinessEngine.acwrGate, "a genuine spike read as \(ratio)")
    }
}

/// The wear check asked how *much* of the day carried samples and never *where* the
/// hole was, and a share cannot localise a hole. Both of its tests were shares of the
/// span, so a gap over the session: the exact thing that makes a load measure lie:
/// had to grow past eight and a half hours before either fired.
@Suite("The wear check needs to know where the hole is")
struct WearGapTests {

    /// Woken at seven, read at eleven at night, worn all day apart from `off`.
    /// A fixed ordinary Thursday, not `Date()`. On a spring-forward day
    /// `startOfDay + 23 h` is the *next* midnight, so the clock floor sees zero minutes
    /// elapsed and switches itself off, which made one of these tests unable to pass at
    /// all on 2027-03-14, and the floor an hour stricter on every fall-back day.
    private var midnight: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 10))!
    }

    private func day(off: Range<Double>? = nil, onAt: Double = 7, bpm: Double = 75,
                     sessionAt: Range<Double>? = nil, sessionBpm: Double = 145,
                     wokeAtHour: Double? = 7, readAtHour: Double = 23) -> StrainInput {
        let midnight = midnight
        var samples: [HeartRateSample] = []
        // Five-minute buckets across the waking day, minus whatever was not worn.
        for step in 0..<Int((readAtHour - onAt) * 12) {
            let hour = onAt + Double(step) / 12
            if let off, off.contains(hour) { continue }
            let rate = (sessionAt?.contains(hour) ?? false) ? sessionBpm : bpm
            samples.append(HeartRateSample(start: midnight.addingTimeInterval(hour * 3600),
                                           minutes: 5, beatsPerMinute: rate))
        }
        return StrainInput(samples: samples, restingHeartRate: 55, ageYears: 35,
                           biologicalSex: .male, hardSets: 0,
                           readAt: midnight.addingTimeInterval(readAtHour * 3600),
                           asleepPeriods: wokeAtHour.map {
                               [DateInterval(start: midnight.addingTimeInterval(($0 - 8) * 3600),
                                             end: midnight.addingTimeInterval($0 * 3600))]
                           } ?? [])
    }

    /// The headline case, and the ordinary one: the watch comes off to train. Ninety
    /// minutes missing out of sixteen hours is a sampled share of 0.91, so the density
    /// test would need a threshold near 0.91 to see it: no calibration of a share can
    /// do this job. Measured before the fix: strain 22.9 against a true 65.5, coverage
    /// `.full`, nothing said.
    @Test("a hole over the session is not a complete record")
    func gapOverSessionFlagged() {
        let result = StrainScore.of(day(off: 10..<11.5, sessionAt: 10..<11.5))
        #expect(result.coverage == .partial,
                "90 minutes missing over the session read as a complete day")
        #expect(result.missing.contains { $0.localizedCaseInsensitiveContains("part of the day") })
        #expect(result.value != nil, "a flagged day still has to produce a number")
    }

    /// Sweeping the hole: every size an hour and over is a hole a session fits in.
    @Test("any missing hour is reported", arguments: [1.0, 1.5, 4.0, 7.0])
    func gapsOfAnHourOrMoreFlagged(hours: Double) {
        let result = StrainScore.of(day(off: 10..<(10 + hours)))
        #expect(result.coverage == .partial, "\(hours) h missing mid-day read as complete")
    }

    /// The other side of the line. A watch off the wrist for a few minutes is how every
    /// watch behaves, and the carry-forward already covers it.
    @Test("a short break is not a missing day", arguments: [0.25, 0.5])
    func shortBreaksAreSilent(hours: Double) {
        #expect(StrainScore.of(day(off: 10..<(10 + hours))).coverage == .full,
                "\(hours * 60) minutes off the wrist was called a missing day")
    }

    /// Round 5's fix, for the third time. With no wake time the window used to start at
    /// the first sample, so the span test became `span < span x 0.5` again: false however
    /// late the watch went on. `wokeAt` is nil whenever the day has no asleep-stage
    /// sample: watch on the charger overnight, iPhone-only sleep, or sleep-analysis
    /// permission declined, which makes it nil on every day, permanently.
    @Test("a watch put on at ten at night says so, wake time or not",
          arguments: [Double?.some(7), Double?.none])
    func lateWearFlaggedWithoutWakeTime(wokeAtHour: Double?) {
        let result = StrainScore.of(day(onAt: 22, wokeAtHour: wokeAtHour))
        #expect(result.coverage == .partial,
                "one hour of trace read as a complete day with wokeAt = \(wokeAtHour as Any)")
    }

    /// And the day that is genuinely complete stays silent, at every hour it gets opened,
    /// with or without a wake time.
    @Test("a fully worn day is never flagged", arguments: [9.0, 12.0, 15.0, 18.0, 23.0])
    func fullDayIsSilent(readAtHour: Double) {
        for wokeAtHour in [Double?.some(7), nil] {
            let result = StrainScore.of(day(wokeAtHour: wokeAtHour, readAtHour: readAtHour))
            #expect(StrainScore.of(day(wokeAtHour: wokeAtHour, readAtHour: readAtHour)).coverage == .full,
                    "flagged at \(readAtHour):00 with wokeAt = \(wokeAtHour as Any): \(result.missing)")
        }
    }
}


/// The clock floor, which is the only thing standing in for a wake time the app does not
/// have. It cannot tell "woke late" from "put the watch on late", nobody can, without a
/// night to read, so it claims only what the clock proves: by this hour, at least
/// `time since midnight - maximumSleepMinutes` of waking day has happened.
@Suite("Standing in for a wake time")
struct WearClockFloorTests {

    private var midnight: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 10))!
    }

    /// Worn without a break from `onAt` to the read, and no night recorded anywhere.
    private func unslept(onAt: Double, readAtHour: Double = 23) -> StrainInput {
        let samples = (0..<Int((readAtHour - onAt) * 12)).map { step in
            HeartRateSample(start: midnight.addingTimeInterval((onAt + Double(step) / 12) * 3600),
                            minutes: 5, beatsPerMinute: 75)
        }
        return StrainInput(samples: samples, restingHeartRate: 55, ageYears: 35,
                           biologicalSex: .male, hardSets: 0,
                           readAt: midnight.addingTimeInterval(readAtHour * 3600))
    }

    /// A lie-in is not a missing day. This is the false positive the allowance exists to
    /// avoid, and at ten hours it started an hour too early.
    @Test("sleeping in is not a missing day", arguments: [8.0, 9.0, 10.0, 10.5])
    func lieInIsSilent(onAt: Double) {
        #expect(StrainScore.of(unslept(onAt: onAt)).coverage == .full,
                "a complete day beginning at \(onAt):00 was called incomplete")
    }

    /// And the floor still has to fire, or the case it exists for walks through: a watch
    /// on the charger all morning, no night recorded, nothing to find a leading gap
    /// against.
    @Test("a morning with no trace at all is still caught", arguments: [12.0, 14.0, 17.0])
    func missingMorningFlagged(onAt: Double) {
        #expect(StrainScore.of(unslept(onAt: onAt)).coverage == .partial,
                "a day that only starts at \(onAt):00 read as complete")
    }

    /// Nothing is claimed before the clock can prove it, whatever the record looks like.
    @Test("early in the day it claims nothing", arguments: [1.0, 6.0, 9.0])
    func earlyReadClaimsNothing(readAtHour: Double) {
        let late = unslept(onAt: readAtHour - 0.5, readAtHour: readAtHour)
        #expect(late.samples.isEmpty || StrainScore.of(late).coverage == .full,
                "flagged at \(readAtHour):00, when no waking day is provable yet")
    }
}

@Suite("Saying how much was recorded")
struct WearMessageTests {

    /// "About 0 hours" is not a sentence about anything. Reachable whenever the watch goes
    /// on within half an hour of a late read.
    @Test("a trace under an hour is described in minutes")
    func shortTraceInMinutes() {
        let midnight = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 10))!
        let samples = [HeartRateSample(start: midnight.addingTimeInterval(22 * 3600),
                                       minutes: 20, beatsPerMinute: 80)]
        let result = StrainScore.of(StrainInput(
            samples: samples, restingHeartRate: 55, ageYears: 35, biologicalSex: .male,
            hardSets: 0, readAt: midnight.addingTimeInterval(23 * 3600)))
        let line = result.missing.first { $0.localizedCaseInsensitiveContains("part of the day") }
        #expect(line?.contains("0 hours") != true, "said \"about 0 hours\": \(line ?? "nothing")")
        #expect(line?.contains("20 minutes") == true, "said \(line ?? "nothing")")
    }
}


/// The breakdown has to add up to the ring, including in the ramp band where a sample's
/// effort is split between training and simply being awake.
///
/// `magnitudesSum` pins this at reserve 0.70, where `trainingShare` is saturated and the
/// split never happens, so the ramp was untested. A trace with no reading below 0.40
/// reserve (a chest strap or a watch put on to train) filed everyday load to zone 0 and
/// no minutes there, and a row is only drawn where there are minutes, so that load
/// disappeared from the breakdown while staying in the ring: 21.19 against rows summing
/// to 10.21, 52% unexplained.
@Suite("The breakdown adds up inside the ramp")
struct RampBandSumTests {

    private func trace(bpm: Double, minutes: Int) -> StrainInput {
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600)
        let samples = (0..<minutes).map {
            HeartRateSample(start: start.addingTimeInterval(Double($0) * 60),
                            minutes: 1, beatsPerMinute: bpm)
        }
        return StrainInput(samples: samples, restingHeartRate: 55, ageYears: 35,
                           biologicalSex: .male, hardSets: 0,
                           readAt: start.addingTimeInterval(Double(minutes) * 60))
    }

    /// 108 bpm is reserve 0.41 for this profile: inside the 0.30–0.55 ramp, and above
    /// the 0.40 line that decides which zone the sample is filed under.
    @Test("a session-only trace inside the ramp still sums",
          arguments: [(108.0, 45), (109.0, 60), (113.0, 90), (105.0, 30)])
    func rampOnlyTraceSums(bpm: Double, minutes: Int) throws {
        let result = StrainScore.of(trace(bpm: bpm, minutes: minutes))
        let value = try #require(result.value)
        let summed = result.contributors.reduce(0) { $0 + $1.magnitude }
        #expect(abs(summed - value) < 0.01,
                "\(minutes) min at \(bpm) bpm: ring \(value), rows \(summed)")
    }

    /// And the minutes still describe the day: no row may claim more of it than happened.
    @Test("the rows do not invent minutes")
    func minutesAreConserved() {
        let result = StrainScore.of(trace(bpm: 108, minutes: 45))
        let minutes = result.contributors
            .filter { $0.unit == "min" }
            .reduce(0) { $0 + ($1.value ?? 0) }
        #expect(abs(minutes - 45) < 0.01, "rows account for \(minutes) of 45 minutes")
    }
}
