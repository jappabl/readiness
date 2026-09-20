import Foundation
import Testing
@testable import ReadinessCore

/// `primarySleepEnd` is the end of the longest asleep episode of the wake day, which is a
/// wake time only when that episode was a night.
///
/// The strain wear check is judged against a window starting at the wake time, so handing
/// it the end of a nap starts the window in the afternoon and everything missed before it
/// stops being a hole. Measured: up at 06:30, a hard session at 07:00 that the watch never
/// saw because it was charging until noon, and a recorded afternoon nap — strain 22.5
/// against a true 73.0, reported as a complete day. The same inputs are caught when the
/// wake time is absent and when it is the real one; the nap is the only thing that hides it.
@Suite("A nap is not a wake time")
struct WakeTimeTests {

    private let calendar = Calendar(identifier: .gregorian)
    private var midnight: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
    }

    private func breakdown(_ episodes: [(Double, Double)]) -> SleepBreakdown {
        let intervals = episodes.map {
            SleepInterval(start: midnight.addingTimeInterval($0.0 * 3600),
                          end: midnight.addingTimeInterval($0.1 * 3600), stage: .core)
        }
        return SleepAggregator.byWakeDay(intervals, calendar: calendar)[
            calendar.startOfDay(for: midnight)]!
    }

    @Test("an afternoon nap is not offered as a wake time")
    func napIsNotAWakeTime() {
        let night = breakdown([(14, 15)])
        #expect(night.primarySleepEnd != nil, "the fixture should still record the nap")
        #expect(night.wakeTime == nil, "a one-hour episode was offered as a wake time")
    }

    @Test("a night is")
    func nightIsAWakeTime() throws {
        let night = breakdown([(-1.0, 7.0)])
        #expect(try #require(night.wakeTime) == midnight.addingTimeInterval(7 * 3600))
    }

    /// A short night is not trusted either, which is the safe direction: the wear check
    /// falls back to what the clock can prove rather than to a window it cannot justify.
    @Test("a broken three-hour night is not trusted", arguments: [1.0, 2.0, 3.5])
    func shortNightIsNotTrusted(hours: Double) {
        #expect(breakdown([(7 - hours, 7)]).wakeTime == nil)
    }

    @Test("and the boundary is the night/nap line")
    func boundary() {
        #expect(breakdown([(7 - SleepBreakdown.minimumNightHours + 0.1, 7)]).wakeTime == nil)
        #expect(breakdown([(7 - SleepBreakdown.minimumNightHours - 0.1, 7)]).wakeTime != nil)
    }

    /// The whole reason the distinction exists: the morning the watch never saw.
    @Test("the morning a nap would have hidden is reported")
    func napDoesNotHideTheMorning() {
        // Watch on the charger until noon, then worn continuously to eleven at night.
        let samples = (0..<Int(11 * 12)).map { step in
            HeartRateSample(start: midnight.addingTimeInterval((12 + Double(step) / 12) * 3600),
                            minutes: 5, beatsPerMinute: 75)
        }
        let nap = breakdown([(14, 15)])
        let result = StrainScore.of(StrainInput(
            samples: samples, restingHeartRate: 55, ageYears: 35, biologicalSex: .male,
            hardSets: 0, readAt: midnight.addingTimeInterval(23 * 3600),
            wokeAt: nap.wakeTime))
        #expect(result.coverage == .partial,
                "a day whose record starts at noon read as complete")
    }
}
