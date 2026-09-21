import Testing
import Foundation
@testable import ReadinessCore

/// The one message that can change tonight instead of describing last night.
@Suite("The bedtime target")
struct BedtimeTargetTests {

    private let bedtime = Date(timeIntervalSince1970: 1_800_000_000)

    private func need(hours: Double, strain: Double = 0) -> SleepNeed {
        SleepNeed(hours: hours, baseline: SleepNeed.baselineHours,
                  strainAdjustment: strain, napCredit: 0, learnedShare: 1)
    }

    @Test("an hour before bed is inside the window")
    func withinWindow() {
        #expect(BedtimeTarget.isDue(now: bedtime.addingTimeInterval(-60 * 60),
                                    usualBedtime: bedtime))
    }

    @Test("the whole afternoon is not")
    func tooEarly() {
        #expect(!BedtimeTarget.isDue(now: bedtime.addingTimeInterval(-5 * 3600),
                                     usualBedtime: bedtime))
    }

    @Test("after bedtime is too late to be useful")
    func tooLate() {
        #expect(!BedtimeTarget.isDue(now: bedtime.addingTimeInterval(30 * 60),
                                     usualBedtime: bedtime))
    }

    // Added in review: none of the brief's three window fixtures (-60min, -5h, +30min)
    // land on the boundary itself, so `secondsUntil <= windowMinutes * 60` could regress
    // to `<` without any test noticing. This pins the edge as inclusive.
    @Test("exactly ninety minutes before bed is still inside the window")
    func exactlyAtTheWindowEdge() {
        #expect(BedtimeTarget.isDue(now: bedtime.addingTimeInterval(-BedtimeTarget.windowMinutes * 60),
                                    usualBedtime: bedtime))
    }

    @Test("an ordinary night says nothing")
    func ordinaryNightIsSilent() {
        #expect(BedtimeTarget.sentence(need: need(hours: 8.1)) == nil)
    }

    @Test("a hard day asks for more, and says why")
    func hardDaySpeaks() {
        let sentence = BedtimeTarget.sentence(
            need: need(hours: 8.75, strain: 0.7), debtHours: 0.1)
        // Formatted through the same locale-dependent `.formatted(.number...)` the
        // production code uses, rather than a hardcoded "8.8": that literal assumes a
        // period decimal separator and fails on a machine whose locale uses a comma —
        // the same class of machine-dependence pinning `calendar` to UTC exists to avoid.
        let expectedHours = 8.75.formatted(.number.precision(.fractionLength(0...1)))
        #expect(sentence?.contains(expectedHours) == true)
        #expect(sentence?.lowercased().contains("yesterday") == true)
    }

    @Test("accumulated debt asks for more, and says that instead")
    func debtSpeaks() {
        let sentence = BedtimeTarget.sentence(
            need: need(hours: 8.8, strain: 0.05), debtHours: 1.4)
        #expect(sentence?.lowercased().contains("behind") == true)
    }

    @Test("the margin is a threshold, not a suggestion")
    func justUnderTheMarginIsSilent() {
        let hours = SleepNeed.baselineHours + BedtimeTarget.unusualMarginHours - 0.01
        #expect(BedtimeTarget.sentence(need: need(hours: hours, strain: 0.7)) == nil)
    }

    @Test("exactly on the margin speaks")
    func onTheMarginSpeaks() {
        let hours = SleepNeed.baselineHours + BedtimeTarget.unusualMarginHours
        #expect(BedtimeTarget.sentence(need: need(hours: hours, strain: 0.7)) != nil)
    }
}
