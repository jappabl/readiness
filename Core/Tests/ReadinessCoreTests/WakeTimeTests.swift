import Foundation
import Testing
@testable import ReadinessCore

/// When the waking day began, which the strain wear check measures everything against.
///
/// Round 7 asked how *long* the day's longest sleep was and trusted it above four hours.
/// Length cannot separate a night from a nap: a broken three-and-a-half-hour night is a
/// night, and a four-and-a-half-hour afternoon sleep is not. That guard was wrong in both
/// directions at once — it hid a 42-point hole after a short night and a 45-point one
/// after a long daytime sleep. When the sleep *started* is what tells them apart.
@Suite("When the day started")
struct WakeTimeTests {

    private let calendar = Calendar(identifier: .gregorian)
    private var midnight: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 10))!
    }

    /// Hours may be negative, for the evening before.
    private func breakdown(_ episodes: [(Double, Double)]) -> SleepBreakdown {
        let intervals = episodes.map {
            SleepInterval(start: midnight.addingTimeInterval($0.0 * 3600),
                          end: midnight.addingTimeInterval($0.1 * 3600), stage: .core)
        }
        return SleepAggregator.byWakeDay(intervals, calendar: calendar)[
            calendar.startOfDay(for: midnight)]!
    }

    private func wake(_ episodes: [(Double, Double)]) -> Date? {
        breakdown(episodes).wakeTime(on: midnight, calendar: calendar)
    }

    @Test("an ordinary night ends the night")
    func ordinaryNight() throws {
        #expect(try #require(wake([(-1, 7)])) == midnight.addingTimeInterval(7 * 3600))
    }

    /// The case round 7 broke. However short, a sleep that ended this morning is the one
    /// the day started from.
    @Test("a short or broken night still starts the day", arguments: [0.75, 2.0, 3.5])
    func shortNightCounts(hours: Double) throws {
        let woke = try #require(wake([(4.5 - hours, 4.5)]))
        #expect(woke == midnight.addingTimeInterval(4.5 * 3600))
    }

    /// And the case it was written for, which stays fixed — at any length.
    @Test("a daytime sleep never starts the day", arguments: [1.0, 4.5, 6.0])
    func daytimeSleepDoesNot(hours: Double) {
        #expect(wake([(17.5 - hours, 17.5)]) == nil)
    }

    /// Six was a bedtime, not a boundary. A night shift ending at six, a new parent, a
    /// red-eye — all went to bed at exactly the hour that stopped qualifying, and had a
    /// perfectly recorded day reported as part-recorded every day.
    @Test("a night that starts at dawn is still a night", arguments: [5.0, 6.0, 7.5, 8.5])
    func lateBedtimeStillANight(hour: Double) throws {
        let woke = try #require(wake([(hour, hour + 7)]))
        #expect(woke == midnight.addingTimeInterval((hour + 7) * 3600))
    }

    /// With both, the night wins, whichever is longer.
    @Test("a night plus a longer afternoon sleep still reports the night")
    func nightBeatsLongerNap() throws {
        let woke = try #require(wake([(-1, 6), (13, 20)]))
        #expect(woke == midnight.addingTimeInterval(6 * 3600))
    }

    @Test("and the line is when it started, not how long it ran")
    func boundary() {
        #expect(wake([(SleepBreakdown.latestWakingStartHour - 0.1, 12)]) != nil)
        #expect(wake([(SleepBreakdown.latestWakingStartHour + 0.1, 12)]) == nil)
    }

    @Test("no sleep at all says nothing")
    func noSleep() {
        #expect(SleepBreakdown().wakeTime(on: midnight, calendar: calendar) == nil)
    }

    /// The periods themselves are carried, merged and in order, because the wear check
    /// needs to know the whole day and not just its start.
    @Test("every stretch of sleep is carried, in order")
    func periodsCarried() {
        let night = breakdown([(-1, 6), (13, 14), (13.5, 15)])
        #expect(night.asleepPeriods.count == 2)
        #expect(night.asleepPeriods[0].start < night.asleepPeriods[1].start)
        // The two overlapping afternoon sleeps are one period, not two.
        #expect(abs(night.asleepPeriods[1].duration / 3600 - 2) < 0.01)
    }
}
