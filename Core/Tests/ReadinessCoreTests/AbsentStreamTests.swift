import Foundation
import Testing
@testable import ReadinessCore

/// What the app says about data it cannot ever have.
///
/// A phone-only sleeper was told every morning that seven nights of stage data for deep
/// sleep, for REM and for awakenings, plus overnight heart rate, were "not counted
/// today". Four reasons, none of which waiting would satisfy, repeated for ever. Their
/// record is complete for the device they own.
///
/// See docs/superpowers/specs/2026-09-20-absent-streams-design.md.
@Suite("A stream nothing can record")
struct AbsentStreamTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// A night with duration and continuity but no staging and no heart rate, which is
    /// exactly what a phone alone records.
    private func phoneOnlyNight(_ daysAgo: Int) -> SleepBreakdown {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: base)!
        let start = calendar.date(bySettingHour: 23, minute: 0, second: 0,
                                  of: calendar.date(byAdding: .day, value: -1, to: day)!)!
        let end = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: day)!
        var night = SleepBreakdown()
        night.asleepHours = 8
        night.asleepPeriods = [DateInterval(start: start, end: end)]
        night.primarySleepStart = start
        night.primarySleepEnd = end
        // One unbroken run, which is what a phone recording a single asleep interval
        // produces. Continuity is not a watch measurement and must keep being listed.
        night.recordedContinuity = 1
        // No stages and no heart rate, which is exactly what a phone alone records.
        return night
    }

    private func phoneOnlyInput(nights: Int) -> SleepInput {
        let history = (1...nights).map { phoneOnlyNight($0) }
        return SleepInput(breakdown: phoneOnlyNight(0), durationHours: 8,
                          history: history,
                          priorNights: Array(repeating: 8.0, count: nights),
                          calendar: calendar)
    }

    @Test("a phone-only sleeper is not told to wait for a sensor they do not own")
    func noStageRowsWithoutAWatch() {
        let score = SleepScore.of(phoneOnlyInput(nights: 30), wearsAWatch: false)
        let listed = score.missing.joined(separator: " | ").lowercased()
        #expect(!listed.contains("stage"), "listed: \(listed)")
        #expect(!listed.contains("heart rate"), "listed: \(listed)")
    }

    @Test("and their record can be complete, because it is")
    func phoneOnlyReachesFull() {
        // The actual complaint: never being able to see a full ring, for ever, for
        // owning the wrong hardware.
        #expect(SleepScore.of(phoneOnlyInput(nights: 30), wearsAWatch: false).coverage == .full)
    }

    @Test("somebody who does own one is still told their watch missed a night")
    func watchOwnersStillHearAboutIt() {
        // The whole point of the distinction: this one is worth a line, because
        // charging the watch fixes it.
        let score = SleepScore.of(phoneOnlyInput(nights: 30), wearsAWatch: true)
        #expect(!score.missing.isEmpty)
        #expect(score.coverage != .full)
    }

    @Test("the score itself does not move")
    func scoringIsUnchanged() {
        // Structural absence already behaves correctly in the maths: a missing component
        // is charged the typical level, which stops a phone scoring 100 on a night a
        // watch could only score 96. This changes what is said, not what is computed.
        let input = phoneOnlyInput(nights: 30)
        #expect(SleepScore.of(input, wearsAWatch: false).value
                == SleepScore.of(input, wearsAWatch: true).value)
    }
}
