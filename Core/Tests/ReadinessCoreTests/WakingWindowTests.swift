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
                           readAt: at(readAtHour), asleepPeriods: asleep)
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
}
