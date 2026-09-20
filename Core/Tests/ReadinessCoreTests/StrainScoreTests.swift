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

    @Test("the anchors sit where the spec says", arguments: [
        (0.0, 0.00), (20.0, 3.55), (40.0, 6.07), (121.6, 12.23),
        (200.0, 15.69), (300.0, 18.74), (400.0, 21.00),
    ])
    func anchors(load: Double, expected: Double) {
        #expect(abs(StrainScore.strain(load: load) - expected) < 0.02,
                "load \(load) gave \(StrainScore.strain(load: load))")
    }

    @Test("the scale stops at 21 rather than running off the end")
    func clamped() {
        #expect(StrainScore.strain(load: 1000) == 21)
        #expect(StrainScore.strain(load: -5) == 0)
    }

    /// Non-linear on purpose: it costs far more to go from 16 to 17 than from 4 to 5.
    @Test("each point costs more than the one before it")
    func logarithmic() {
        let early = StrainScore.load(strain: 5) - StrainScore.load(strain: 4)
        let late = StrainScore.load(strain: 17) - StrainScore.load(strain: 16)
        #expect(late > early * 3)
    }

    @Test("bands follow the scale", arguments: [
        (0.0, ScoreBand.light), (9.9, .light), (10.0, .moderate), (13.9, .moderate),
        (14.0, .hard), (17.9, .hard), (18.0, .allOut), (21.0, .allOut),
    ])
    func bands(value: Double, expected: ScoreBand) {
        #expect(ScoreBand.strain(value: value) == expected)
    }
}

@Suite("Muscular load")
struct MuscularLoadTests {

    /// Lifting is invisible to a heart rate measure — a heavy triple barely moves the
    /// average — so hard sets carry their own load, and Insights shows both.
    @Test("twenty hard sets is worth forty")
    func hardSets() {
        #expect(StrainScore.muscularLoad(hardSets: 20) == 40)
    }

    @Test("a lifting session with no cardiac trace still produces strain")
    func liftingAlone() throws {
        let result = StrainScore.of(input(hardSets: 20))
        let value = try #require(result.value)
        #expect(value > 5, "20 hard sets read as \(value)")
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
        let result = StrainScore.of(input(minutes(40, at: 150), hardSets: 6))
        #expect(result.coverage == .full)
        #expect(result.missing.isEmpty)
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
