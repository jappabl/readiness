import Foundation
import Testing
@testable import ReadinessCore

/// A night can be recorded as asleep without being classified into stages — an
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

    /// And a night classified in the same proportions gives the same stage reading,
    /// whatever share of it the watch got round to labelling.
    ///
    /// Asserted on the stage rows rather than on the whole score, because continuity is a
    /// different measurement that genuinely depends on how the intervals fall, and this
    /// fixture changes that when it leaves part of the night unspecified.
    @Test("the same night, less of it labelled, reads the same")
    func proportionalPartialIsUnchanged() throws {
        let full = score(1)
        for classified in [0.95, 0.9, 0.8] {
            let partial = score(classified)
            for id in ["deep", "rem"] {
                let a = try #require(full.contributor(id))
                let b = try #require(partial.contributor(id))
                #expect(abs((a.level ?? 0) - (b.level ?? 0)) < 0.001,
                        "\(id) level moved at \(Int(classified * 100))%: \(a.level as Any) vs \(b.level as Any)")
                #expect(abs((a.value ?? 0) - (b.value ?? 0)) < 0.001,
                        "\(id) hours moved at \(Int(classified * 100))%: \(a.value as Any) vs \(b.value as Any)")
            }
        }
    }

    /// The inversion exactly as it was measured: a night with no staging at all scored
    /// 97.50 while the same night two-thirds classified scored 94.00, because the
    /// unclassified third was charged to the stages as zeros. Knowing less about a night
    /// must never be worth more than knowing more.
    @Test("knowing nothing about the structure beats knowing some of it")
    func unstagedNeverBeatsStaged() throws {
        let unstaged = try #require(score(0).value)
        for classified in [0.75, 0.8, 0.9, 1.0] {
            let partial = try #require(score(classified).value)
            #expect(unstaged <= partial + 0.001,
                    "no staging scored \(unstaged) against \(partial) at \(Int(classified * 100))%")
        }
    }

    /// Below that, the record is not describing the night's structure and must not be
    /// read as though a stage were missing rather than unmeasured.
    @Test("a barely classified night says the stages are missing, not zero",
          arguments: [0.6, 0.4, 0.2])
    func barelyClassifiedIsMissing(classified: Double) {
        let result = score(classified)
        #expect(result.contributor("deep") == nil,
                "deep was scored off \(Int(classified * 100))% of the night")
        #expect(result.contributor("rem") == nil)
        #expect(result.missing.contains { $0.localizedCaseInsensitiveContains("stage") },
                "nothing on screen says the stages were not read: \(result.missing)")
    }

    /// The published hours still fit the night, in this direction too.
    @Test("published stage hours still fit the night", arguments: [1.0, 0.9, 0.8])
    func stagesFit(classified: Double) throws {
        let result = score(classified)
        let deep = try #require(result.contributor("deep")?.value)
        let rem = try #require(result.contributor("rem")?.value)
        #expect(deep + rem <= 8.001)
    }
}
