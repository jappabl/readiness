import Foundation
import Testing
@testable import ReadinessCore

/// A night can be recorded as asleep without being classified into stages: an
/// `unspecified` run from a second source, a watch that only staged part of the night.
///
/// `isStaged` asked only whether *any* stage was recorded, so one staged sample made the
/// whole night count as fully described and every unclassified hour was charged to the
/// stages as a zero. Two things broke. Measuring less scored *higher* than measuring
/// nothing at all, which is the inversion `typicalComponentLevel` exists to prevent. And
/// the app named a stage the device never classified as the night's worst component,
/// which is verbatim the failure `isStaged`'s own comment says it is there to stop.
@Suite("A night the watch only partly classified")
struct PartialStagingTests {

    private let calendar = Calendar(identifier: .gregorian)

    private func date(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: 7))!
    }

    /// Eight hours asleep, of which `classified` is broken into stages in the usual
    /// proportions and the rest is recorded as asleep but unclassified.
    private func night(_ day: Int, classified: Double) -> SleepBreakdown {
        let end = date(day)
        let start = end.addingTimeInterval(-8 * 3600)
        var cursor = start
        func slice(_ hours: Double, _ stage: SleepStage) -> SleepInterval {
            let interval = SleepInterval(start: cursor,
                                         end: cursor.addingTimeInterval(hours * 3600),
                                         stage: stage)
            cursor = cursor.addingTimeInterval(hours * 3600)
            return interval
        }
        let staged = 8 * classified
        let samples = [slice(staged * 0.15, .deep), slice(staged * 0.25, .rem),
                       slice(staged * 0.60, .core), slice(8 - staged, .unspecified)]
        return SleepAggregator.byWakeDay(samples, calendar: calendar)[
            calendar.startOfDay(for: end)]!
    }

    private func score(_ classified: Double) -> SignalScore {
        let tonight = night(1, classified: classified)
        return SleepScore.of(SleepInput(
            breakdown: tonight, durationHours: tonight.asleepHours,
            history: (2...15).map { night($0, classified: 1) },
            strain: nil, napHours: nil, sleepingHeartRate: nil, daytimeHeartRate: nil,
            calendar: calendar))
    }

    /// The fixture has to actually under-classify, or none of this means anything.
    @Test("the fixture really does leave part of the night unclassified")
    func fixtureUnderClassifies() {
        let tonight = night(1, classified: 0.8)
        #expect(abs(tonight.asleepHours - 8) < 0.01)
        #expect(abs((tonight.deepHours + tonight.remHours + tonight.coreHours) - 6.4) < 0.01)
    }

    /// The inversion, stated directly. Nothing about measuring a smaller share of the
    /// night may make it read better.
    @Test("measuring less of the night never scores higher")
    func lessMeasuredNeverScoresHigher() throws {
        let full = try #require(score(1).value)
        for classified in [0.95, 0.9, 0.8, 0.75, 0.6, 0.5, 0.3, 0.1] {
            let partial = try #require(score(classified).value)
            #expect(partial <= full + 0.001,
                    "\(Int(classified * 100))% classified scored \(partial) against \(full)")
        }
    }

    /// The hours nothing labelled are light sleep, not a share of deep and REM.
    ///
    /// Scaling the labelled part up to fill the night is what invented deep sleep that
    /// never happened. Giving the remainder to light invents nothing: deep and REM are
    /// exactly the hours something actually recorded, and the night still adds up.
    @Test("unlabelled hours become light sleep and never deep or REM",
          arguments: [0.96, 0.9, 0.8, 0.6, 0.4, 0.2])
    func unlabelledBecomesLight(classified: Double) throws {
        let tonight = night(1, classified: classified)
        let stages = try #require(tonight.reconciledStages)
        #expect(abs(stages.deep - tonight.deepHours) < 0.001,
                "deep was moved from the \(tonight.deepHours) h that was recorded")
        #expect(abs(stages.rem - tonight.remHours) < 0.001)
        #expect(abs(stages.deep + stages.rem + stages.core - tonight.asleepHours) < 0.001,
                "the stages do not add up to the night")
        #expect(stages.core >= tonight.coreHours - 0.001,
                "the unlabelled hours went somewhere other than light")
    }

    /// Both directions of the same rule. Over-counting is still scaled down to fit,
    /// because two sources labelling the whole night and merely disagreeing about which
    /// stage it was is a proportional error, and the night cannot hold nine hours.
    @Test("two sources that between them stage more than the night still fit in it")
    func overCountStillFits() throws {
        let end = date(1)
        let start = end.addingTimeInterval(-8 * 3600)
        func slice(_ from: Double, _ to: Double, _ stage: SleepStage) -> SleepInterval {
            SleepInterval(start: start.addingTimeInterval(from * 3600),
                          end: start.addingTimeInterval(to * 3600), stage: stage)
        }
        // One source calls the whole night core, another stages the same hours.
        let night = SleepAggregator.byWakeDay(
            [slice(0, 8, .core), slice(0, 1.5, .deep), slice(1.5, 3.5, .rem)],
            calendar: calendar)[calendar.startOfDay(for: end)]!
        let stages = try #require(night.reconciledStages)
        #expect(abs(stages.deep + stages.rem + stages.core - night.asleepHours) < 0.001,
                "\(stages) does not fit an \(night.asleepHours) h night")
        #expect(stages.deep < night.deepHours + 0.001, "deep was not scaled down to fit")
    }

    /// A night a watch staged nearly all of still gets broken down.
    ///
    /// The bar was 97%, which sounds like a rounding allowance and is not: a second
    /// source logging the same night as plain asleep over a slightly wider window adds
    /// to the total without adding to the staged hours, so a watch that labelled all of
    /// its own record lands at 95% of somebody else's. Hao wore a watch all night, read
    /// "stages cover 7.9 h of an 8.1 h night", and got no breakdown at all. Neither
    /// device was wrong and there was nothing for him to fix.
    @Test("a night missing a few minutes of labelling is still broken down",
          arguments: [0.99, 0.96, 0.93, 0.9])
    func nearlyFullyLabelledIsBrokenDown(classified: Double) {
        let result = score(classified)
        #expect(result.contributor("deep") != nil,
                "\(Int(classified * 100))% classified got no deep sleep row")
        #expect(result.contributor("rem") != nil)
    }

    /// The failure the old floor existed to stop, pinned at the root instead.
    ///
    /// Rescaling the labelled part to fill the night named a different stage as the
    /// night's worst than the full record did on more than half of 600 measured nights,
    /// swinging up to 6.7 points either way. The floor answered that by withholding the
    /// whole breakdown below 97%, which cost every two-source sleeper their stage ring
    /// every night for a quarter of an hour of drift.
    ///
    /// Nothing is withheld now, and nothing is invented either: deep and REM are the
    /// hours something actually recorded, and the unlabelled remainder is light. There
    /// is no arithmetic left that can inflate a stage, which is what the floor was for.
    @Test("a partly labelled night never reports more deep or REM than was recorded",
          arguments: [0.96, 0.9, 0.84, 0.8, 0.76, 0.5, 0.2])
    func underCountIsNotExtrapolated(classified: Double) throws {
        let tonight = night(1, classified: classified)
        let result = score(classified)
        let deep = try #require(result.contributor("deep")?.value)
        let rem = try #require(result.contributor("rem")?.value)
        #expect(deep <= tonight.deepHours + 0.001,
                "deep read \(deep) h off \(tonight.deepHours) h of record")
        #expect(rem <= tonight.remHours + 0.001,
                "REM read \(rem) h off \(tonight.remHours) h of record")
    }

    /// The specific shape that made it wrong, rather than the share: staging that starts
    /// late. The labelled slice is missing the front of the night, where deep sleep
    /// concentrates, so extrapolating it accused deep of a shortfall that never happened.
    @Test("a late start does not get a stage blamed for it")
    func lateStartBlamesNothing() {
        let end = date(1)
        let start = end.addingTimeInterval(-8 * 3600)
        func slice(_ from: Double, _ to: Double, _ stage: SleepStage) -> SleepInterval {
            SleepInterval(start: start.addingTimeInterval(from * 3600),
                          end: start.addingTimeInterval(to * 3600), stage: stage)
        }
        // Asleep for the whole eight hours; staged only from 1.6 h in, and the deep that
        // happened before then is simply not in the record.
        let night = SleepAggregator.byWakeDay(
            [slice(0, 1.6, .unspecified), slice(1.6, 2.6, .deep),
             slice(2.6, 4.6, .rem), slice(4.6, 8, .core)],
            calendar: calendar)[calendar.startOfDay(for: end)]!
        let result = SleepScore.of(SleepInput(
            breakdown: night, durationHours: night.asleepHours,
            history: (2...15).map { self.night($0, classified: 1) },
            strain: nil, napHours: nil, sleepingHeartRate: nil, daytimeHeartRate: nil,
            calendar: calendar))
        // The row exists now, because the hour of deep sleep in the record is real and
        // worth seeing. What may not happen is the app inflating it to cover the 1.6 h
        // nothing labelled, or naming it the reason the night was poor.
        #expect(result.contributor("deep")?.value ?? 0 <= night.deepHours + 0.001,
                "deep was stretched over a record that starts after the deep sleep does")
        #expect(result.summary.localizedCaseInsensitiveContains("deep") == false,
                "the summary blamed deep: \(result.summary)")
    }

    /// The inversion exactly as it was measured: a night with no staging at all scored
    /// 97.50 while the same night two-thirds classified scored 94.00, because the
    /// unclassified third was charged to the stages as zeros. Knowing less about a night
    /// must never be worth more than knowing more.
    @Test("knowing nothing about the structure beats knowing some of it")
    func unstagedNeverBeatsStaged() throws {
        let unstaged = try #require(score(0).value)
        for classified in [0.98, 1.0] {
            let partial = try #require(score(classified).value)
            #expect(unstaged <= partial + 0.001,
                    "no staging scored \(unstaged) against \(partial) at \(Int(classified * 100))%")
        }
    }

    /// A night mostly unlabelled shows what it measured and says what it did with the
    /// rest. The hours went to light, which is a choice rather than a measurement, and
    /// a night measured light looks identical on the ring to one nothing finished
    /// reading. Only the words can tell them apart, so the words have to be there.
    @Test("a barely classified night says how much of it carried no label",
          arguments: [0.6, 0.4, 0.2])
    func barelyClassifiedSaysSo(classified: Double) throws {
        let result = score(classified)
        #expect(result.contributor("deep") != nil)
        #expect(result.coverage != .full, "a barely read night claimed a complete record")
        #expect(result.missing.contains { $0.localizedCaseInsensitiveContains("counted as light") },
                "nothing says the unlabelled hours were counted as light: \(result.missing)")
    }

    /// The published hours still fit the night, in this direction too.
    @Test("published stage hours still fit the night", arguments: [1.0, 0.99])
    func stagesFit(classified: Double) throws {
        let result = score(classified)
        let deep = try #require(result.contributor("deep")?.value)
        let rem = try #require(result.contributor("rem")?.value)
        #expect(deep + rem <= 8.001)
    }

    /// A night the watch did not finish labelling loses its stage rows, and each one is
    /// charged a stand-in a shade under a good night. That stand-in is a constant, and
    /// every constant sits above some nights and below others, so a gap is a small
    /// penalty on a night better than your usual and a bonus on one worse than it.
    /// Measured against a sleeper's own distribution: -2.0 well above usual, -1.6 at it,
    /// +6.9 a little below, +8.0 clearly poor.
    ///
    /// It cannot be tuned away. The components are scored *self-relatively*, so "your
    /// recent nights were poor" is not a thing this model can know, a consistently poor
    /// sleeper scores near the top against their own history every night. The only stand-in
    /// that never pays a bonus is one at the floor, which would penalise every gap instead.
    /// What is pinned here is that the effect stays bounded and the night always says it
    /// was not fully read.
    @Test("a gap moves the score a little, and always says so")
    func gapIsBoundedAndDisclosed() throws {
        let history = (2...15).map { night($0, classified: 1) }
        let measured = try #require(SleepScore.of(input(night(1, classified: 1),
                                                        history: history)).value)
        let unread = SleepScore.of(input(night(1, classified: 0.8), history: history))
        #expect(abs(try #require(unread.value) - measured) < 10,
                "a gap moved the score from \(measured) to \(unread.value as Any)")
        #expect(unread.coverage != .full, "an unread night claimed a complete record")
        #expect(unread.missing.contains { $0.localizedCaseInsensitiveContains("counted as light") },
                "nothing said what became of the unlabelled hours: \(unread.missing)")
    }

    private func input(_ breakdown: SleepBreakdown,
                       history: [SleepBreakdown]) -> SleepInput {
        SleepInput(breakdown: breakdown, durationHours: breakdown.asleepHours,
                   history: history, strain: nil, napHours: nil,
                   sleepingHeartRate: nil, daytimeHeartRate: nil, calendar: calendar)
    }
}
