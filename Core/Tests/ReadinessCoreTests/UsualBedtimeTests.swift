import Foundation
import Testing
@testable import ReadinessCore

/// When this person usually goes to bed, as a moment tonight.
///
/// The bedtime message is the only one the app sends before the thing it is about, so it
/// needs a time to aim at. The trap is midnight: bedtimes are a clock, not a number, and
/// averaging 23:40 with 00:20 arithmetically gives noon.
@Suite("Tonight's usual bedtime")
struct UsualBedtimeTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// A bedtime `daysAgo` nights back, at the given clock time.
    private func night(_ daysAgo: Int, at hour: Int, _ minute: Int = 0) -> Date {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: base))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private var now: Date {
        calendar.date(bySettingHour: 19, minute: 0, second: 0,
                      of: calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)))!
    }

    private func tonight(_ bedtimes: [Date]) -> Date? {
        UsualBedtime.tonight(from: bedtimes, now: now, calendar: calendar)
    }

    @Test("too few nights is not a habit")
    func needsEnoughNights() {
        let few = (1...(UsualBedtime.minimumNights - 1)).map { night($0, at: 23) }
        #expect(tonight(few) == nil)
        #expect(tonight([]) == nil)
    }

    @Test("a steady sleeper gets their own hour, tonight")
    func steadyBedtime() throws {
        let nights = (1...10).map { night($0, at: 23, 10) }
        let result = try #require(tonight(nights))
        #expect(calendar.component(.hour, from: result) == 23)
        #expect(calendar.component(.minute, from: result) == 10)
        #expect(calendar.isDate(result, inSameDayAs: now), "tonight, not some past night")
    }

    @Test("bedtimes either side of midnight do not average to lunchtime")
    func midnightDoesNotWrapToNoon() throws {
        // The bug this exists for: 23:40 and 00:20 as minutes-since-midnight are 1420
        // and 20, whose mean is 720, which is midday.
        let nights = (1...10).map { index in
            index.isMultiple(of: 2) ? night(index, at: 23, 40) : night(index, at: 0, 20)
        }
        let result = try #require(tonight(nights))
        let hour = calendar.component(.hour, from: result)
        #expect(hour >= 23 || hour == 0, "landed at \(hour) o'clock")
    }

    @Test("a bedtime after midnight is tomorrow, not this morning")
    func afterMidnightIsAhead() throws {
        let nights = (1...10).map { night($0, at: 1, 15) }
        let result = try #require(tonight(nights))
        #expect(result > now, "a target already past is not a target")
        #expect(calendar.component(.hour, from: result) == 1)
    }

    @Test("one wild night does not move it")
    func medianIgnoresAnOutlier() throws {
        var nights = (1...9).map { night($0, at: 22, 30) }
        nights.append(night(10, at: 4))
        let result = try #require(tonight(nights))
        #expect(calendar.component(.hour, from: result) == 22)
    }

    @Test("only the recent stretch counts")
    func ignoresAncientHistory() throws {
        // A habit changed a month ago is not this person's bedtime now.
        let old = (40...60).map { night($0, at: 1) }
        let recent = (1...8).map { night($0, at: 22) }
        let result = try #require(tonight(old + recent))
        #expect(calendar.component(.hour, from: result) == 22)
    }
}
