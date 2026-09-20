import Foundation
import Testing
@testable import ReadinessCore

// Sleep need, and the score built on it.
// See docs/superpowers/specs/2026-09-19-signal-scores-design.md.

@Suite("Sleep need")
struct SleepNeedTests {

    @Test("a rested week needs the baseline and nothing more")
    func noDebt() {
        let need = SleepNeed.of(priorNights: Array(repeating: 8.0, count: 7))
        #expect(need.hours == SleepNeed.baselineHours)
        #expect(need.debt == 0)
    }

    /// Debt accumulates: three nights an hour short is the same hole as one very bad
    /// night, which is the whole argument for tracking it rather than judging each
    /// night alone.
    @Test("short nights accumulate into a debt")
    func debtAccumulates() {
        let need = SleepNeed.of(priorNights: Array(repeating: 7.0, count: 3) + Array(repeating: 8.0, count: 4))
        #expect(need.debt > 0)
        #expect(need.hours > SleepNeed.baselineHours)
    }

    /// A night repays part of the hole, not all of it. Asking somebody to sleep
    /// fourteen hours to clear a week of five-hour nights is advice nobody can take.
    @Test("one night is not asked to repay the whole debt")
    func partialRepayment() {
        let need = SleepNeed.of(priorNights: Array(repeating: 5.0, count: 7))
        #expect(need.hours < SleepNeed.baselineHours + need.debt)
        #expect(need.hours <= SleepNeed.maximumHours)
    }

    @Test("debt is capped so a terrible month cannot demand a whole night extra")
    func debtCapped() {
        let need = SleepNeed.of(priorNights: Array(repeating: 2.0, count: 7))
        #expect(need.debt <= SleepNeed.maximumDebtHours)
    }

    @Test("a hard day asks for more sleep")
    func strainRaisesNeed() {
        // Strain is on 0...100 now, like the other two signals.
        let easy = SleepNeed.of(priorNights: Array(repeating: 8.0, count: 7), strain: 20)
        let hard = SleepNeed.of(priorNights: Array(repeating: 8.0, count: 7), strain: 95)
        #expect(hard.hours > easy.hours)
        #expect(easy.hours == SleepNeed.baselineHours, "an easy day adds nothing")
    }

    @Test("a nap is credited against tonight")
    func napCredit() {
        let without = SleepNeed.of(priorNights: Array(repeating: 8.0, count: 7))
        let with = SleepNeed.of(priorNights: Array(repeating: 8.0, count: 7), napHours: 1)
        #expect(with.hours < without.hours)
    }

    @Test("a three hour nap is not credited as three hours")
    func napCapped() {
        let need = SleepNeed.of(priorNights: Array(repeating: 8.0, count: 7), napHours: 3)
        #expect(need.napCredit <= SleepNeed.maximumNapCreditHours)
    }

    @Test("need stays inside a range a person can actually act on")
    func clamped() {
        let extreme = SleepNeed.of(priorNights: Array(repeating: 0.0, count: 7),
                                   strain: 100, napHours: 0)
        #expect(extreme.hours <= SleepNeed.maximumHours)
        let minimal = SleepNeed.of(priorNights: Array(repeating: 12.0, count: 7), napHours: 3)
        #expect(minimal.hours >= SleepNeed.minimumHours)
    }

    @Test("no history at all is the baseline, not a guess")
    func noHistory() {
        #expect(SleepNeed.of(priorNights: []).hours == SleepNeed.baselineHours)
    }

    /// Was written when each night's shortfall was measured against that night's own
    /// escalating need. It is measured against the flat baseline now — that escalation
    /// was the ratchet — but the property it was really asserting still holds: a week of
    /// short nights owes more than a single short night.
    @Test("a short week owes more than a single short night")
    func recursiveNeed() {
        // Kept under the cap on both sides, or the property is untestable: with the cap
        // at 1.5 hours a single six-hour night already reaches it.
        let flat = SleepNeed.of(priorNights: [8, 8, 8, 8, 8, 8, 7.5])
        let compounding = SleepNeed.of(priorNights: [7.5, 7.5, 7.5, 8, 8, 8, 8])
        #expect(compounding.debt > flat.debt)
    }
}

@Suite("Sleep score")
struct SleepScoreCalculationTests {

    var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    func date(_ day: Int, _ hour: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    /// A night of `hours` asleep ending at 07:00, split into the stage shares given.
    func night(_ day: Int, hours: Double = 8, deep: Double = 0.15, rem: Double = 0.22,
               awake: Double = 0) -> SleepBreakdown {
        let end = date(day)
        let start = end.addingTimeInterval(-(hours + awake) * 3600)
        var cursor = start
        func slice(_ length: Double, _ stage: SleepStage) -> SleepInterval {
            let interval = SleepInterval(start: cursor, end: cursor.addingTimeInterval(length * 3600),
                                         stage: stage)
            cursor = cursor.addingTimeInterval(length * 3600)
            return interval
        }
        let samples = [slice(hours * deep, .deep), slice(awake, .awake),
                       slice(hours * rem, .rem), slice(hours * (1 - deep - rem), .core)]
        return SleepAggregator.byWakeDay(samples, calendar: calendar)[calendar.startOfDay(for: end)]!
    }

    func history(_ count: Int = 14) -> [SleepBreakdown] {
        (1...count).map { night($0 + 1) }
    }

    func input(_ breakdown: SleepBreakdown?, hours: Double?, history: [SleepBreakdown] = [],
               priorNights: [Double] = Array(repeating: 8.0, count: 7),
               strain: Double? = nil, napHours: Double? = nil,
               sleepingHeartRate: Double? = nil, daytimeHeartRate: Double? = nil) -> SleepInput {
        SleepInput(breakdown: breakdown, durationHours: hours, history: history,
                   priorNights: priorNights, strain: strain, napHours: napHours,
                   sleepingHeartRate: sleepingHeartRate, daytimeHeartRate: daytimeHeartRate,
                   calendar: calendar)
    }

    @Test("meeting your need with a clean night is near the top of the scale")
    func goodNight() throws {
        let result = SleepScore.of(input(night(19), hours: 8, history: history()))
        let value = try #require(result.value)
        #expect(value > 90, "a full clean night read as \(value)")
    }

    /// The point of a need-relative score: the same eight hours is not the same result
    /// when you are six hours in the hole.
    @Test("the same night scores lower against a larger need")
    func needMovesTheScore() throws {
        let rested = SleepScore.of(input(night(19), hours: 8, history: history()))
        let indebted = SleepScore.of(input(night(19), hours: 8, history: history(),
                                           priorNights: Array(repeating: 5.0, count: 7)))
        #expect(try #require(indebted.value) < #require(rested.value))
    }

    @Test("half your need is nowhere near half a good night's score")
    func shortNight() throws {
        let result = SleepScore.of(input(night(19, hours: 4), hours: 4, history: history()))
        let value = try #require(result.value)
        #expect(value < 55, "four hours read as \(value)")
    }

    /// Kept from the old engine, which was right about this: eight broken hours are not
    /// eight hours.
    @Test("awakenings cost a night that is otherwise the same length")
    func continuityCosts() throws {
        let clean = SleepScore.of(input(night(19), hours: 8, history: history()))
        let broken = SleepScore.of(input(night(19, awake: 2), hours: 8, history: history()))
        #expect(try #require(broken.value) < #require(clean.value))
    }

    /// Structure is judged against the sleeper's own nights, never an invented ideal.
    /// This is the constraint carried over from docs/briefs/signal-scores.md, and the
    /// reason deep and REM can be scored at all without claiming a clinical target.
    @Test("a poor night of structure loses to the sleeper's own normal")
    func structureScoredAgainstSelf() throws {
        let usual = history()
        let shallow = night(19, deep: 0.03, rem: 0.08)
        let typical = night(19)
        let poor = SleepScore.of(input(shallow, hours: 8, history: usual))
        let normal = SleepScore.of(input(typical, hours: 8, history: usual))
        #expect(try #require(poor.value) < #require(normal.value))
    }

    /// The same absolute deep share is good news for one person and bad for another.
    @Test("the same stage share reads differently against different histories")
    func stageIsRelative() throws {
        let tonight = night(19, deep: 0.12, rem: 0.20)
        let lowSleeper = (1...14).map { night($0 + 1, deep: 0.05, rem: 0.12) }
        let highSleeper = (1...14).map { night($0 + 1, deep: 0.22, rem: 0.28) }
        let againstLow = SleepScore.of(input(tonight, hours: 8, history: lowSleeper))
        let againstHigh = SleepScore.of(input(tonight, hours: 8, history: highSleeper))
        #expect(try #require(againstLow.value) > #require(againstHigh.value))
    }

    /// Duration has to dominate. A beautifully structured five hours is still five hours.
    @Test("structure cannot rescue a short night")
    func qualityIsBounded() throws {
        let perfect = SleepScore.of(input(night(19, hours: 5), hours: 5, history: history(),
                                          sleepingHeartRate: 48, daytimeHeartRate: 70))
        let value = try #require(perfect.value)
        #expect(value <= 100 * (5.0 / 8.0), "structure lifted a 5 hour night to \(value)")
    }

    @Test("the heart rate dip is read when both rates are there")
    func heartRateDip() throws {
        let deep = SleepScore.of(input(night(19), hours: 8, history: history(),
                                       sleepingHeartRate: 50, daytimeHeartRate: 70))
        let shallow = SleepScore.of(input(night(19), hours: 8, history: history(),
                                          sleepingHeartRate: 68, daytimeHeartRate: 70))
        #expect(try #require(deep.value) > #require(shallow.value))
        #expect(deep.contributors.contains { $0.id == SleepScore.dipContributorID })
    }

    @Test("sleeping longer than your need does not push past the top")
    func cappedAtNeed() throws {
        let result = SleepScore.of(input(night(19, hours: 12), hours: 12, history: history()))
        #expect(try #require(result.value) <= 100)
    }

    @Test("bands follow the scale", arguments: [
        (100.0, ScoreBand.green), (85.0, .green), (84.9, .yellow),
        (70.0, .yellow), (69.9, .red), (0.0, .red),
    ])
    func bands(percent: Double, expected: ScoreBand) {
        #expect(ScoreBand.sleep(percent: percent) == expected)
    }
}

@Suite("Sleep contributions")
struct SleepContributionTests {

    var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 7))!
    }
    func night(_ day: Int, hours: Double = 8) -> SleepBreakdown {
        let end = date(day)
        let start = end.addingTimeInterval(-hours * 3600)
        let samples = [
            SleepInterval(start: start, end: start.addingTimeInterval(hours * 0.15 * 3600), stage: .deep),
            SleepInterval(start: start.addingTimeInterval(hours * 0.15 * 3600),
                          end: start.addingTimeInterval(hours * 0.37 * 3600), stage: .rem),
            SleepInterval(start: start.addingTimeInterval(hours * 0.37 * 3600), end: end, stage: .core),
        ]
        return SleepAggregator.byWakeDay(samples, calendar: calendar)[calendar.startOfDay(for: end)]!
    }

    func input(_ hours: Double) -> SleepInput {
        SleepInput(breakdown: night(19, hours: hours), durationHours: hours,
                   history: (1...14).map { night($0 + 1) },
                   priorNights: Array(repeating: 8.0, count: 7),
                   calendar: calendar)
    }

    /// Sleep counts down from a full night, so the rows are what the night cost.
    @Test("sleep counts down from one hundred")
    func neutralIsOneHundred() {
        #expect(SleepScore.of(input(8)).neutral == 100)
    }

    @Test("contributor magnitudes sum to the distance from a full night")
    func magnitudesSum() throws {
        for hours in [4.0, 6.0, 7.5, 8.0] {
            let result = SleepScore.of(input(hours))
            let value = try #require(result.value)
            let summed = result.contributors.reduce(0) { $0 + $1.magnitude }
            #expect(abs(summed - (value - 100)) < 0.01,
                    "\(hours)h: rows sum to \(summed), score sits \(value - 100) from full")
        }
    }

    @Test("nothing a short night lost is credited as a gain")
    func lossesAreNegative() {
        #expect(SleepScore.of(input(5)).contributors.allSatisfy { $0.magnitude <= 0.001 })
    }

    @Test("time asleep leads the breakdown when the night was short")
    func durationLeads() {
        #expect(SleepScore.of(input(4.5)).contributors.first?.id == SleepScore.durationContributorID)
    }
}

@Suite("Sleep coverage")
struct SleepCoverageTests {

    /// Reverses the old engine deliberately. It refused a score without continuity, on
    /// the reasoning that hours alone cannot establish quality — which is true, and is
    /// why the number is labelled rather than withheld. A phone-only sleeper got no ring
    /// at all, and a missing ring tells them less than a measured duration does.
    @Test("duration alone still produces a labelled score")
    func durationOnly() {
        let result = SleepScore.of(SleepInput(breakdown: nil, durationHours: 7,
                                              priorNights: Array(repeating: 8.0, count: 7)))
        #expect(result.value != nil)
        // Duration alone leaves every structural component unmeasured, which is a
        // baseline still being built rather than one thing not counted today.
        #expect(result.coverage == .buildingBaseline)
        #expect(result.missing.contains { $0.localizedCaseInsensitiveContains("stage") })
    }

    @Test("no sleep recorded is no score rather than a zero")
    func nothingRecorded() {
        let result = SleepScore.of(SleepInput(breakdown: nil, durationHours: nil))
        #expect(result.value == nil)
        #expect(result.coverage == .unavailable)
    }

    @Test("nonsense durations stay missing")
    func invalidDuration() {
        for value in [Double.nan, .infinity, -1, 0] {
            #expect(SleepScore.of(SleepInput(breakdown: nil, durationHours: value)).value == nil)
        }
    }

    /// A component without enough nights behind it is dropped from the average and named,
    /// rather than scored against a baseline built from three nights.
    @Test("a component with too little history is excluded and named")
    func thinHistory() {
        let result = SleepScore.of(SleepInput(breakdown: nil, durationHours: 8,
                                              history: [], priorNights: [8, 8, 8]))
        #expect(result.coverage != .full)
        #expect(!result.missing.isEmpty)
    }
}

@Suite("Sleep debt is not a ratchet")
struct SleepDebtRepaymentTests {

    /// The defect this suite exists for. Debt used to be measured against each night's
    /// own escalating need and could only ever rise, so it compounded about half an hour
    /// a night and nothing repaid it.
    @Test("a run of long nights repays a bad one")
    func surplusRepays() {
        let need = SleepNeed.of(priorNights: [3, 10, 10, 10, 10, 10, 10])
        #expect(need.debt == 0, "six ten-hour nights left a debt of \(need.debt)")
        #expect(need.hours == SleepNeed.baselineHours)
    }

    /// Six minutes of habitual sleep used to cost sixteen points and a band: 8.0 h gave
    /// a need of 8.0 and 7.9 h gave the maximum 9.5, so a 7.9-hour sleeper and a 5-hour
    /// sleeper were told exactly the same thing.
    @Test("there is no cliff just under eight hours")
    func noCliff() {
        let eight = SleepNeed.of(priorNights: Array(repeating: 8.0, count: 7))
        let justUnder = SleepNeed.of(priorNights: Array(repeating: 7.9, count: 7))
        #expect(justUnder.hours - eight.hours < 0.5,
                "7.9h asked for \(justUnder.hours), 8.0h asked for \(eight.hours)")
    }

    /// Ordinary night-to-night variance was enough to pin the need at its maximum, which
    /// put somebody averaging eight and a half hours in the yellow.
    @Test("a normal week that averages enough owes nothing", arguments: [
        [7.5, 8.5, 7.8, 8.2, 7.6, 8.4, 8.0],
        [7.5, 9.5, 7.5, 9.5, 7.5, 9.5, 8.5],
        [5.0, 8.5, 8.5, 8.5, 8.5, 8.5, 8.5],
    ])
    func varianceIsNotDebt(nights: [Double]) {
        #expect(SleepNeed.of(priorNights: nights).debt < 0.01)
    }

    /// The same seven numbers in a different order used to give a different answer.
    @Test("the order of a week does not change what it owes")
    func orderIndependent() {
        let week = [6.0, 9.0, 7.0, 9.5, 6.5, 8.5, 7.5]
        #expect(SleepNeed.of(priorNights: week).debt
                == SleepNeed.of(priorNights: week.reversed()).debt)
    }

    /// Still has to work: genuine chronic shortfall is what the mechanism is for.
    @Test("a genuinely short week still owes")
    func realDebtSurvives() {
        let need = SleepNeed.of(priorNights: Array(repeating: 6.0, count: 7))
        #expect(need.debt == SleepNeed.maximumDebtHours)
        #expect(need.hours > SleepNeed.baselineHours)
    }
}

@Suite("Measuring less never scores higher")
struct SleepCoverageFairnessTests {

    var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 7))!
    }
    /// `staged` false records the night the way a watch on a charger does: asleep, with
    /// no stage detail at all.
    func night(_ day: Int, hours: Double = 8, staged: Bool = true) -> SleepBreakdown {
        let end = date(day)
        let start = end.addingTimeInterval(-hours * 3600)
        let samples: [SleepInterval] = staged
            ? [SleepInterval(start: start, end: start.addingTimeInterval(hours * 0.15 * 3600), stage: .deep),
               SleepInterval(start: start.addingTimeInterval(hours * 0.15 * 3600),
                             end: start.addingTimeInterval(hours * 0.37 * 3600), stage: .rem),
               SleepInterval(start: start.addingTimeInterval(hours * 0.37 * 3600), end: end, stage: .core)]
            : [SleepInterval(start: start, end: end, stage: .unspecified)]
        return SleepAggregator.byWakeDay(samples, calendar: calendar)[calendar.startOfDay(for: end)]!
    }

    func score(_ breakdown: SleepBreakdown?, staged: Bool = true) -> SignalScore {
        SleepScore.of(SleepInput(breakdown: breakdown, durationHours: 8,
                                 history: (1...14).map { night($0 + 1, staged: staged) },
                                 priorNights: Array(repeating: 8.0, count: 7),
                                 sleepingHeartRate: 56, daytimeHeartRate: 66,
                                 calendar: calendar))
    }

    /// A phone with no sensors used to outscore an Apple Watch on the same night,
    /// because every component it could not see was averaged in as flawless.
    @Test("an unmeasured night cannot beat a measured good one")
    func blindDoesNotWin() throws {
        let measured = try #require(score(night(19)).value)
        let unmeasured = try #require(
            SleepScore.of(SleepInput(breakdown: nil, durationHours: 8,
                                     priorNights: Array(repeating: 8.0, count: 7))).value)
        #expect(unmeasured <= measured,
                "measuring nothing scored \(unmeasured), measuring everything scored \(measured)")
    }

    /// A night recorded as plain "asleep" has no stages. That is not the same as a night
    /// with no deep sleep in it, and the app used to say the second thing.
    @Test("an unstaged night is not a night with no deep sleep")
    func unstagedIsNotZero() {
        let result = score(night(19, staged: false))
        #expect(result.contributor("deep")?.value != 0,
                "an unstaged night reported a measured zero hours of deep sleep")
        #expect(result.missing.contains { $0.localizedCaseInsensitiveContains("deep") })
    }

    /// Being exactly your own normal is not a fault, and used to cost about five points
    /// with the leading explanation naming a value identical to the person's average.
    @Test("a completely typical night scores near the top")
    func typicalNightIsNotPunished() throws {
        let value = try #require(score(night(19)).value)
        #expect(value > 95, "an utterly ordinary night scored \(value)")
    }
}
