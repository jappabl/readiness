import Foundation
import Testing
@testable import ReadinessCore

/// The wear check has to know which parts of the day the person was awake for, and a
/// single wake instant cannot express that.
///
/// Round 7 guarded it by episode length: trust `primarySleepEnd` only for an episode of
/// four hours or more. Length cannot separate a night from a nap — a 3.5-hour night is a
/// night and a 4.5-hour afternoon sleep is not — so that guard broke it in both
/// directions at once. A recorded short night switched the leading-gap check off entirely
/// and hid a 42-point hole; a long daytime sleep still pointed the window at the evening
/// and hid 45 points; and any episode the guard refused to trust was cut out of the trace
/// anyway and then counted as unworn time, flagging watches that never came off.
@Suite("The waking part of the day")
struct WakingWindowTests {

    private let calendar = Calendar(identifier: .gregorian)
    private var midnight: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
    }
    private func at(_ hour: Double) -> Date { midnight.addingTimeInterval(hour * 3600) }

    /// `hour` may be negative for the evening before.
    private func sleep(_ from: Double, _ to: Double) -> [DateInterval] {
        [DateInterval(start: at(from), end: at(to))]
    }

    /// Worn continuously between the hours given, minus any holes.
    private func day(worn: [(Double, Double)], asleep: [DateInterval],
                     primary: DateInterval? = nil,
                     sessionAt: Range<Double>? = nil, readAtHour: Double = 22)
    -> StrainInput {
        var samples: [HeartRateSample] = []
        for (from, to) in worn {
            for step in 0..<Int((to - from) * 12) {
                let hour = from + Double(step) / 12
                let rate = (sessionAt?.contains(hour) ?? false) ? 158.0 : 75.0
                samples.append(HeartRateSample(start: at(hour), minutes: 5,
                                               beatsPerMinute: rate))
            }
        }
        return StrainInput(samples: samples, restingHeartRate: 55, ageYears: 35,
                           biologicalSex: .male, hardSets: 0,
                           readAt: at(readAtHour), asleepPeriods: asleep,
                           // Unless a case names one, the night is the longest episode,
                           // which is how `SleepAggregator` picks it in production.
                           primarySleep: primary
                               ?? asleep.max(by: { $0.duration < $1.duration }))
    }

    /// A night is whatever ended this morning, however short. Three and a half hours of
    /// recorded sleep used to make the app stop looking at the morning at all.
    @Test("a short night still says when the day started", arguments: [1.0, 2.0, 3.5, 7.0])
    func shortNightStillStartsTheDay(hours: Double) {
        let result = StrainScore.of(day(worn: [(10, 22)],
                                        asleep: sleep(4.5 - hours, 4.5),
                                        sessionAt: 8..<9))
        #expect(result.coverage == .partial,
                "a \\(hours) h night left the morning unexamined")
    }

    /// And a sleep in the afternoon is not a statement about when the day began, however
    /// long it ran.
    @Test("a daytime sleep does not start the day", arguments: [1.0, 4.5, 6.0])
    func daytimeSleepDoesNotStartTheDay(hours: Double) {
        let result = StrainScore.of(day(worn: [(17.5, 22)],
                                        asleep: sleep(17.5 - hours, 17.5),
                                        sessionAt: 9..<10))
        #expect(result.coverage == .partial,
                "a \\(hours) h afternoon sleep hid the whole morning")
    }

    /// The inverse error, and the commoner one: time asleep is not time unrecorded, so a
    /// watch that never came off must not be reported as a part-recorded day.
    @Test("sleep in the middle of the day is not a hole in the record")
    func sleepIsNotAHole() {
        for asleep in [sleep(1.5, 5), sleep(14, 15), sleep(13, 15), sleep(3, 3.75)] {
            let result = StrainScore.of(day(worn: [(0, 22)], asleep: asleep))
            #expect(result.coverage == .full,
                    "a continuously worn watch was flagged around \\(asleep): \\(result.missing)")
        }
    }

    /// An ordinary night, an ordinary day, nothing to say.
    @Test("a normal day is silent", arguments: [9.0, 13.0, 18.0, 22.0])
    func normalDayIsSilent(readAtHour: Double) {
        let result = StrainScore.of(day(worn: [(7, readAtHour)], asleep: sleep(-1, 7),
                                        readAtHour: readAtHour))
        #expect(result.coverage == .full, "flagged at \\(readAtHour):00: \\(result.missing)")
    }

    /// And the hole still has to be found when it is genuinely there.
    @Test("a hole in the waking day is still reported")
    func realHoleStillFound() {
        let result = StrainScore.of(day(worn: [(7, 10), (12, 22)], asleep: sleep(-1, 7),
                                        sessionAt: 10..<11.5))
        #expect(result.coverage == .partial)
    }

    /// A staged night fragments at every awake segment, and the day's start was inferred
    /// from where the *first* fragment ended. When that fell before local midnight the
    /// inference pointed at yesterday, nothing could qualify, and the leading-gap check
    /// switched off entirely: 50 points hidden and reported as a complete record, decided
    /// by which side of midnight somebody happened to stir.
    @Test("a night that stirs before midnight still says when the day started",
          arguments: [-1.75, -1.0, -0.5, 0.5, 1.5])
    func brokenNightBeforeMidnight(blipAt: Double) {
        let night = [DateInterval(start: at(-2), end: at(blipAt)),
                     DateInterval(start: at(blipAt + 0.17), end: at(6.5))]
        let result = StrainScore.of(day(worn: [(9, 22)], asleep: night, sessionAt: 7..<8.5))
        #expect(result.coverage == .partial,
                "a blip at \(blipAt) hid the morning: \(result.missing)")
    }

    /// The wake time is when the night ended, not when its first fragment did. A
    /// five-minute misread before the real night, or ninety minutes awake in the middle of
    /// it, used to make the window start there and call the rest of the night a hole.
    @Test("a fragment is not the end of the night")
    func fragmentIsNotWaking() {
        let misread = [DateInterval(start: at(0.08), end: at(0.17)),
                       DateInterval(start: at(1), end: at(8))]
        #expect(StrainScore.of(day(worn: [(8, 22)], asleep: misread)).coverage == .full,
                "a five-minute misread before the night was called a hole")
        let brokenNight = [DateInterval(start: at(-1), end: at(1)),
                           DateInterval(start: at(2.5), end: at(7))]
        #expect(StrainScore.of(day(worn: [(7, 22)], asleep: brokenNight)).coverage == .full,
                "ninety minutes awake mid-night was called a hole")
    }

    /// A past day runs to its own midnight, and the sleep that starts that evening belongs
    /// to the next wake day — so it was never subtracted, and every past day was reported
    /// as part-recorded for anybody who does not sleep in their watch.
    @Test("an evening is not a hole on a day that is over", arguments: [20.0, 21.0, 22.0])
    func eveningSleepIsNotAHole(offAt: Double) {
        let night = [DateInterval(start: at(-2), end: at(7)),
                     DateInterval(start: at(offAt + 0.5), end: at(31))]
        let result = StrainScore.of(day(worn: [(7, offAt)], asleep: night, readAtHour: 24))
        #expect(result.coverage == .full,
                "watch off at \(offAt):00 on a finished day: \(result.missing)")
    }

    /// A second sleep early in the day is not when the day started.
    ///
    /// Taking the *last* qualifying period fixed a five-minute misread starting the window
    /// too early, and broke the other direction: any second episode beginning before nine
    /// dragged the window start to *its* end, so everything before it stopped being
    /// examined — and because a wake time was then found, the clock floor was switched off
    /// too, leaving no second net. Measured at 41 and 50 points, reported as complete.
    @Test("a morning lie-down does not erase the morning before it")
    func secondSleepDoesNotStartTheDay() {
        // Up at 06:00, a hard hour at 06:15 the watch never saw, back to sleep 08:30.
        let night = DateInterval(start: at(-1), end: at(6))
        let lieDown = DateInterval(start: at(8.5), end: at(11))
        let result = StrainScore.of(day(worn: [(11, 22)], asleep: [night, lieDown],
                                        primary: night, sessionAt: 6.25..<7.25))
        #expect(result.coverage == .partial,
                "the 06:00-08:30 window was never looked at: \(result.missing)")
    }

    /// The same for a doze an hour after waking.
    @Test("a doze after waking does not start the day")
    func dozeDoesNotStartTheDay() {
        let night = DateInterval(start: at(-2), end: at(4))
        let doze = DateInterval(start: at(5), end: at(6))
        let result = StrainScore.of(day(worn: [(6, 22)], asleep: [night, doze],
                                        primary: night))
        #expect(result.coverage == .partial, "04:00-05:00 was never looked at")
    }

    /// And the cases the "last period" rule was introduced for stay fixed, because the
    /// primary episode spans its own awake bridges.
    @Test("a misread and a mid-night wake are still not holes")
    func fragmentsStillFine() {
        let misread = DateInterval(start: at(0.08), end: at(0.17))
        let night = DateInterval(start: at(1), end: at(8))
        #expect(StrainScore.of(day(worn: [(8, 22)], asleep: [misread, night],
                                   primary: night)).coverage == .full,
                "a five-minute misread was called a hole")
        let firstHalf = DateInterval(start: at(-1), end: at(1))
        let secondHalf = DateInterval(start: at(2.5), end: at(7))
        #expect(StrainScore.of(day(worn: [(7, 22)], asleep: [firstHalf, secondHalf],
                                   primary: DateInterval(start: at(-1), end: at(7)))).coverage == .full,
                "ninety minutes awake mid-night was called a hole")
    }

    /// The start-hour test has to be a wall clock, not elapsed seconds, or it moves by an
    /// hour on the two days a year the clocks change. Same class as the day-end bug.
    @Test("the cutoff is a clock hour")
    func cutoffIsWallClock() {
        let early = DateInterval(start: at(8.5), end: at(14))
        #expect(WakingDay.start(of: [early], primary: early, on: midnight,
                                calendar: calendar) != nil)
        let late = DateInterval(start: at(9.5), end: at(15))
        #expect(WakingDay.start(of: [late], primary: late, on: midnight,
                                calendar: calendar) == nil)
    }
}
