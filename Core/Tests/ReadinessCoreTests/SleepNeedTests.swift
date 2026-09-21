import Foundation
import Testing
@testable import ReadinessCore

// Sleep need, and the score built on it.
// See docs/superpowers/specs/2026-09-19-signal-scores-design.md.

@Suite("Sleep need")
struct SleepNeedTests {

    /// The redesign: debt no longer moves the need. It used to, and over sixty nights it
    /// made a constant 7h30 sleeper change band on 44% of them: the cap parked almost
    /// every need on the same number and left people a fraction of a point from a
    /// boundary. It also put a hard ceiling on anyone habitually under 7h26m. The stock
    /// lives in `SleepDebt` now and feeds recovery, which is the question it answers.
    @Test("a run of short nights does not raise tonight's need")
    func debtDoesNotMoveTheNeed() {
        #expect(SleepNeed.of().hours == SleepNeed.baselineHours)
        #expect(SleepNeed.of(strain: 0).hours == SleepNeed.baselineHours)
    }

    @Test("a hard day asks for more sleep")
    func strainRaisesNeed() {
        let easy = SleepNeed.of(strain: 20)
        let hard = SleepNeed.of(strain: 95)
        #expect(hard.hours > easy.hours)
        #expect(easy.hours == SleepNeed.baselineHours, "an easy day adds nothing")
    }

    /// Small enough that it cannot park anybody on a band edge, which is the failure the
    /// debt term produced.
    @Test("the hard-day adjustment is bounded")
    func strainBounded() {
        #expect(SleepNeed.of(strain: 100).strainAdjustment == SleepNeed.strainExtraHours)
        #expect(SleepNeed.of(strain: 100).hours
                <= SleepNeed.baselineHours + SleepNeed.strainExtraHours)
    }

    @Test("a nap is credited against tonight")
    func napCredit() {
        #expect(SleepNeed.of(napHours: 1).hours < SleepNeed.of().hours)
    }

    @Test("a three hour nap is not credited as three hours")
    func napCapped() {
        #expect(SleepNeed.of(napHours: 3).napCredit <= SleepNeed.maximumNapCreditHours)
    }

    @Test("need stays inside a range a person can actually act on")
    func clamped() {
        #expect(SleepNeed.of(strain: 100).hours <= SleepNeed.maximumHours)
        #expect(SleepNeed.of(napHours: 3).hours >= SleepNeed.minimumHours)
    }

    @Test("nonsense inputs do not move it")
    func nonsense() {
        #expect(SleepNeed.of(strain: .nan).hours == SleepNeed.baselineHours)
        #expect(SleepNeed.of(napHours: -5).hours == SleepNeed.baselineHours)
    }
}

@Suite("Sleep debt")
struct SleepDebtTests {

    /// Fourteen settled nights, so the reference has something real to sit on.
    private func settled(_ hours: Double, _ count: Int = 14) -> [Double] {
        Array(repeating: hours, count: count)
    }

    /// The defect that drove the rewrite: accruing against the score's need: the upper
    /// part of the sleeper's own distribution, above their average by construction:
    /// multiplied that bias by fourteen. Somebody averaging a solid eight hours carried
    /// a standing balance of 4.2 h, and an ordinary weekday/weekend sleeper sat pinned
    /// at the cap on 53 days out of 60. The balance measured their variance, not their
    /// sleep. It accrues against their own median now.
    @Test("a settled sleeper owes nothing, however long they sleep")
    func settledOwesNothing() {
        for hours in [7.0, 7.5, 8.0, 8.5, 9.0] {
            #expect(SleepDebt.of(nights: settled(hours)).hours < 0.01,
                    "a steady \(hours) h sleeper was told they were behind")
        }
    }

    /// And variance alone must not become a balance.
    @Test("an ordinary week of ups and downs owes nothing")
    func varianceIsNotDebt() {
        let week = [7.2, 8.4, 7.6, 8.8, 6.9, 9.4, 8.1]
        #expect(SleepDebt.of(nights: week + week).hours < 1.0)
    }

    @Test("a genuinely bad run shows")
    func badRunShows() {
        let nights = settled(8.0, 7) + Array(repeating: 5.0, count: 5)
        #expect(SleepDebt.of(nights: nights).hours > 2)
    }

    /// The one thing a self-relative reference cannot see on its own: somebody
    /// chronically short has a median that ratifies the shortage. Floored at seven.
    @Test("chronic shortage is still caught")
    func chronicCaught() {
        #expect(SleepDebt.of(nights: settled(5.5)).hours > 5,
                "a habitual 5.5 h sleeper was told they owed nothing")
    }

    /// A floor at zero stopped a good night paying anything down and made the balance a
    /// ratchet. Credit is allowed now, bounded.
    @Test("long nights pay it down")
    func surplusRepays() {
        let dug = settled(8.0, 7) + Array(repeating: 5.0, count: 4)
        let dugOut = dug + Array(repeating: 10.0, count: 4)
        #expect(SleepDebt.of(nights: dugOut).hours < SleepDebt.of(nights: dug).hours)
    }

    @Test("but credit does not accumulate without bound")
    func creditBounded() {
        #expect(SleepDebt.of(nights: settled(8.0, 7) + Array(repeating: 11.0, count: 14)).hours < 1.0)
    }

    @Test("the balance is capped")
    func capped() {
        #expect(SleepDebt.of(nights: Array(repeating: 1.0, count: 20)).hours
                == SleepDebt.maximumHours)
    }

    /// The arrow has to agree with the number above it. Both balances are accumulated
    /// against the same reference over windows a night apart; re-learning it between
    /// them made the arrow disagree on 66 days out of 70 and point the wrong way on 27.
    @Test("the change matches what the balance actually did")
    func changeIsHonest() {
        let before = settled(8.0, 10) + [6.0]
        let after = before + [5.0]
        let moved = SleepDebt.of(nights: after).hours - SleepDebt.of(nights: before).hours
        #expect(abs(SleepDebt.of(nights: after).change - moved) < 0.01,
                "arrow said \(SleepDebt.of(nights: after).change), balance moved \(moved)")
    }

    /// Held below the cap on both sides, or the worse night has nowhere left to go.
    @Test("a long night reads as progress and a bad one does not")
    func progressIsNegative() {
        let dug = settled(8.0, 10) + Array(repeating: 6.5, count: 2)
        #expect(SleepDebt.of(nights: dug + [10.5]).change < 0)
        #expect(SleepDebt.of(nights: dug + [4.0]).change > 0)
    }

    /// A night stops mattering by fading, not by falling off an edge. The edge was the
    /// problem: it produced eighteen points of recovery across two mornings when nothing
    /// the sleeper did had changed.
    @Test("an old night stops counting")
    func ancientNightForgotten() {
        #expect(SleepDebt.of(nights: [1.0] + settled(8.0, 14)).hours < 1.0)
        #expect(SleepDebt.of(nights: [1.0] + settled(8.0, 30)).hours < 0.1)
    }

    /// And it fades rather than vanishing. The settled nights before it hold the
    /// reference still, so every step below is the decay and nothing else.
    @Test("a bad night fades instead of dropping out")
    func badNightFades() {
        let balances = (0...12).map { after in
            SleepDebt.of(nights: settled(7.5, 20) + [3.0] + settled(7.5, after)).hours
        }
        #expect(balances[0] > 4, "the bad night barely registered: \(balances[0])")
        #expect(zip(balances, balances.dropFirst()).allSatisfy { $1 < $0 },
                "not monotonic: \(balances)")
        // No single morning may carry more than a fifth of the recovery, which is the
        // whole complaint about the hard window: it delivered the lot in two.
        let steps = zip(balances, balances.dropFirst()).map { $0 - $1 }
        #expect(steps.max()! < balances[0] * 0.2,
                "one morning moved \(steps.max()!) of \(balances[0]): \(balances)")
    }

    /// The other thing the window got wrong: against a fixed edge, sleeping exactly your
    /// own median paid back nothing, because the balance only moved when a night entered
    /// or left it.
    @Test("sleeping your own normal pays the balance down")
    func normalNightsPayDown() {
        let after = SleepDebt.of(nights: settled(7.5, 20) + [3.0] + settled(7.5, 3))
        let before = SleepDebt.of(nights: settled(7.5, 20) + [3.0])
        #expect(after.hours < before.hours * 0.7,
                "three ordinary nights moved it from \(before.hours) to \(after.hours)")
        #expect(after.change < 0, "the card would show no progress")
    }

    @Test("nonsense nights are dropped rather than carried")
    func nonsense() {
        #expect(SleepDebt.of(nights: [.nan, 8, .infinity, 8]).hours.isFinite)
        #expect(SleepDebt.of(nights: []).hours == 0)
        #expect(SleepDebt.of(nights: []).change == 0)
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
               strain: Double? = nil, napHours: Double? = nil,
               sleepingHeartRate: Double? = nil, daytimeHeartRate: Double? = nil) -> SleepInput {
        SleepInput(breakdown: breakdown, durationHours: hours, history: history,
                   strain: strain, napHours: napHours,
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
    /// Was "the same night scores lower against a larger need", which is the behaviour
    /// the redesign removed: a running debt balance no longer moves the need, because
    /// it made identical nights score differently for a reason nobody could act on that
    /// night. What remains is yesterday's load, which really is a property of the night
    /// that had to repair it.
    @Test("a night after a hard day is judged against a larger need")
    func needMovesTheScore() throws {
        let easy = SleepScore.of(input(night(19), hours: 8, history: history(), strain: 20))
        let hard = SleepScore.of(input(night(19), hours: 8, history: history(), strain: 100))
        #expect(try #require(hard.value) < #require(easy.value))
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
    /// the reasoning that hours alone cannot establish quality, which is true, and is
    /// why the number is labelled rather than withheld. A phone-only sleeper got no ring
    /// at all, and a missing ring tells them less than a measured duration does.
    @Test("duration alone still produces a labelled score")
    func durationOnly() {
        let result = SleepScore.of(SleepInput(breakdown: nil, durationHours: 7,
                                              history: []))
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
                                              history: []))
        #expect(result.coverage != .full)
        #expect(!result.missing.isEmpty)
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
                                 sleepingHeartRate: 56, daytimeHeartRate: 66,
                                 calendar: calendar))
    }

    /// A phone with no sensors used to outscore an Apple Watch on the same night,
    /// because every component it could not see was averaged in as flawless.
    @Test("an unmeasured night cannot beat a measured good one")
    func blindDoesNotWin() throws {
        let measured = try #require(score(night(19)).value)
        let unmeasured = try #require(
            SleepScore.of(SleepInput(breakdown: nil, durationHours: 8)).value)
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

@Suite("A need learned from your own nights")
struct LearnedSleepNeedTests {

    /// Eight hours is a population average, and it was the only number in the app
    /// applied to a person rather than learned from them.
    @Test("too little history falls back to the population figure")
    func needsHistory() {
        #expect(SleepNeed.baseline(from: Array(repeating: 7.2, count: 5)).hours
                == SleepNeed.baselineHours)
        #expect(SleepNeed.baseline(from: []).hours == SleepNeed.baselineHours)
    }

    /// The trap the estimator has to avoid: scoring somebody against their own median
    /// hands a chronically under-slept person full marks for staying under-slept.
    @Test("a genuinely short sleeper is not marked down for it")
    func shortSleeper() {
        let nights = Array(repeating: 7.2, count: 30)
        let need = SleepNeed.baseline(from: nights).hours
        #expect(need < SleepNeed.baselineHours)
        #expect(need >= SleepNeed.learnedFloorHours)
    }

    @Test("a long sleeper is held to their own longer need")
    func longSleeper() {
        #expect(SleepNeed.baseline(from: Array(repeating: 9.1, count: 30)).hours > 9)
    }

    /// Somebody restricted on weekdays and free at weekends has told us what they take
    /// when nothing stops them, and it is the weekend number.
    @Test("the estimate follows the unrestricted nights, not the average one")
    func weekendsCount() {
        let weeks = (0..<5).flatMap { _ in [6.0, 6.0, 6.0, 6.0, 6.0, 9.4, 9.4] }
        let need = SleepNeed.baseline(from: weeks).hours
        #expect(need > 8.5, "learned \(need) from a week of six-hour nights and long weekends")
    }

    /// The one case the estimate cannot be trusted. If even their long nights are short
    /// there is no unrestricted night anywhere in the record, so the number would measure
    /// how constrained they are rather than what they need, and lowering the bar for the
    /// person furthest from clearing it is the wrong direction to be wrong in.
    @Test("no relief anywhere falls back rather than ratifying the deprivation")
    func chronicallyRestricted() {
        let nights = Array(repeating: 5.8, count: 40)
        #expect(SleepNeed.baseline(from: nights).hours == SleepNeed.baselineHours)
    }

    @Test("the estimate is bounded at both ends")
    func bounded() {
        #expect(SleepNeed.baseline(from: Array(repeating: 12.0, count: 30)).hours
                == SleepNeed.learnedCeilingHours)
        #expect(SleepNeed.baseline(from: Array(repeating: 2.0, count: 30)).hours
                == SleepNeed.baselineHours)
    }

    /// Debt is owed against what you need, not against a figure from a table.
    @Test("the debt uses the same learned need")
    func debtFollowsTheNeed() {
        let longSleeper = Array(repeating: 9.2, count: 20) + [8.0]
        #expect(SleepDebt.of(nights: longSleeper).hours > 0,
                "eight hours is a shortfall for somebody who needs nine")
        let shortSleeper = Array(repeating: 7.2, count: 20) + [8.0]
        #expect(SleepDebt.of(nights: shortSleeper).hours == 0)
    }
}

@Suite("The learned need does not lower its own bar")
struct LearnedNeedRampTests {

    /// The ramp was added to kill a twelve-point cliff and inverted the estimator's
    /// purpose: sitting BELOW the floor, it handed a flat 6.9-hour sleeper a need of
    /// 7.12 and a permanent green, while a weekday/weekend sleeper getting more sleep on
    /// average sat non-green on 43 nights out of 60.
    @Test("a habitually short sleeper is still held to the population figure",
          arguments: [6.0, 6.5, 6.8, 6.9, 7.0])
    func shortSleeperNotLetOff(hours: Double) {
        #expect(SleepNeed.baseline(from: Array(repeating: hours, count: 40)).hours
                == SleepNeed.baselineHours,
                "a flat \(hours) h sleeper was handed their own shortage as a target")
    }

    @Test("but somebody who genuinely sleeps less is")
    func genuinelyShortIsLearned() {
        let need = SleepNeed.baseline(from: Array(repeating: 7.6, count: 40)).hours
        #expect(need < SleepNeed.baselineHours && need > 7.2)
    }

    /// Continuous, which is the property the ramp exists for.
    @Test("nothing steps")
    func continuous() {
        var previous = SleepNeed.baseline(from: Array(repeating: 6.0, count: 40)).hours
        for tenths in stride(from: 6.0, through: 9.6, by: 0.05) {
            let need = SleepNeed.baseline(from: Array(repeating: tenths, count: 40)).hours
            #expect(abs(need - previous) < 0.35, "a step at \(tenths) h: \(previous) -> \(need)")
            previous = need
        }
    }

    /// The night count was a threshold too: switching from the population figure to the
    /// learned one in one step moved an unchanged sleeper up to eleven points overnight.
    @Test("the switch from the population figure is gradual")
    func learningIsGradual() {
        var previous = SleepNeed.baselineHours
        for count in SleepNeed.learningNights...(SleepNeed.learningNights * 2 + 4) {
            let need = SleepNeed.baseline(from: Array(repeating: 7.6, count: count)).hours
            #expect(abs(need - previous) < 0.1,
                    "night \(count) moved the need \(previous) -> \(need)")
            previous = need
        }
    }
}

@Suite("The debt card can see somebody improving")
struct SleepDebtResolutionTests {

    /// At a fortnight, against a reference floored at seven hours, the balance saturated
    /// for anybody whose median was under 6.5, so a six-hour sleeper who genuinely
    /// improved to six and a half watched the card read the same number for forty days.
    /// That is precisely the group the floor exists to catch.
    @Test("improvement shows before the balance is cleared")
    func improvementIsVisible() {
        let stuck = SleepDebt.of(nights: Array(repeating: 6.0, count: 20)).hours
        let better = SleepDebt.of(nights: Array(repeating: 6.5, count: 20)).hours
        let nearlyThere = SleepDebt.of(nights: Array(repeating: 6.9, count: 20)).hours
        #expect(better < stuck, "6.5 h read the same as 6.0 h")
        #expect(nearlyThere < better, "6.9 h read the same as 6.5 h")
    }

    /// And a bad run inside a healthy habit still reaches the top.
    @Test("a bad week still maxes it")
    func badWeekStillMaxes() {
        let nights = Array(repeating: 7.5, count: 20) + Array(repeating: 5.0, count: 5)
        #expect(SleepDebt.of(nights: nights).hours == SleepDebt.maximumHours)
    }

    @Test("a steady sleeper still owes nothing")
    func steadyOwesNothing() {
        #expect(SleepDebt.of(nights: Array(repeating: 7.5, count: 20)).hours < 0.01)
    }
}

/// The balance has to fade per night that *passed*, not per night that was recorded.
///
/// `accumulate` applied the decay once per array entry, and the array had already had its
/// unrecorded nights compacted out, so taking the watch off froze the balance instead of
/// letting it fade, and the sentence on screen ("each night fades as it recedes rather
/// than dropping out on a fixed day") was false for exactly the people most likely to
/// read it.
@Suite("A night nobody recorded still passes")
struct SleepDebtCalendarTests {

    private func nights(_ hours: Double, _ count: Int) -> [Double?] {
        Array(repeating: Double?.some(hours), count: count)
    }

    private var badWeek: [Double?] { nights(7.5, 20) + nights(4.0, 7) }

    @Test("an unrecorded night still fades the balance", arguments: [3, 5, 7, 14])
    func unrecordedNightsStillDecay(gap: Int) {
        let frozen = SleepDebt.of(nights: badWeek).hours
        let afterGap = SleepDebt.of(nights: badWeek + Array(repeating: nil, count: gap)).hours
        #expect(afterGap < frozen * 0.9,
                "\(gap) unrecorded nights left it at \(afterGap) of \(frozen)")
    }

    /// But an unrecorded night is not a good night: not wearing the watch cannot pay the
    /// balance down faster than actually sleeping would.
    @Test("a missing night is not a night of credit")
    func missingIsNotCredit() {
        let unrecorded = SleepDebt.of(nights: badWeek + Array(repeating: nil, count: 5)).hours
        let slept = SleepDebt.of(nights: badWeek + nights(9.5, 5)).hours
        #expect(slept < unrecorded, "sleeping nine hours paid less than not recording")
    }

    /// And a record with nothing in it is not a record of anything.
    @Test("nothing recorded owes nothing")
    func emptyOwesNothing() {
        #expect(SleepDebt.of(nights: Array(repeating: nil, count: 30)).hours == 0)
    }
}
