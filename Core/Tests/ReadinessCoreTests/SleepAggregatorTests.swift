import Testing
import Foundation
@testable import ReadinessCore

@Suite("Aggregating a night of sleep")
struct SleepAggregatorTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: day,
                                           hour: hour, minute: minute))!
    }

    private func day(_ d: Int) -> Date {
        calendar.startOfDay(for: date(d, 12))
    }

    @Test("a night is attributed to the day you woke up on, not the day you lay down")
    func attributedToWakeDay() {
        let night = [SleepInterval(start: date(10, 23), end: date(11, 6), stage: .core)]
        let result = SleepAggregator.byWakeDay(night, calendar: calendar)

        #expect(result[day(11)]?.asleepHours == 7)
        #expect(result[day(10)] == nil, "nothing should land on the night you fell asleep")
    }

    @Test("time awake and time merely in bed are not time asleep")
    func awakeAndInBedExcluded() {
        let night = [
            SleepInterval(start: date(10, 22), end: date(11, 7), stage: .inBed),
            SleepInterval(start: date(10, 23), end: date(11, 3), stage: .core),
            SleepInterval(start: date(11, 3), end: date(11, 3, 30), stage: .awake),
            SleepInterval(start: date(11, 3, 30), end: date(11, 6), stage: .deep),
        ]
        let result = SleepAggregator.byWakeDay(night, calendar: calendar)
        let breakdown = result[day(11)]

        #expect(breakdown?.asleepHours == 6.5, "four core hours plus two and a half deep")
        #expect(breakdown?.awakeHours == 0.5)
        #expect(breakdown?.inBedHours == 9)
    }

    @Test("stages sum to the total asleep")
    func stagesSumToAsleep() {
        let night = [
            SleepInterval(start: date(10, 23), end: date(11, 1), stage: .core),
            SleepInterval(start: date(11, 1), end: date(11, 3), stage: .deep),
            SleepInterval(start: date(11, 3), end: date(11, 5), stage: .rem),
            SleepInterval(start: date(11, 5), end: date(11, 6), stage: .unspecified),
        ]
        let breakdown = SleepAggregator.byWakeDay(night, calendar: calendar)[day(11)]

        #expect(breakdown?.coreHours == 2)
        #expect(breakdown?.deepHours == 2)
        #expect(breakdown?.remHours == 2)
        #expect(breakdown?.asleepHours == 7, "including the unspecified hour")
    }

    @Test("a phone and a watch recording the same night do not double it")
    func overlappingSourcesAreNotDoubleCounted() {
        let night = [
            SleepInterval(start: date(10, 23), end: date(11, 6), stage: .core),
            SleepInterval(start: date(10, 23, 30), end: date(11, 5, 30), stage: .core),
        ]
        let breakdown = SleepAggregator.byWakeDay(night, calendar: calendar)[day(11)]

        #expect(breakdown?.asleepHours == 7, "the union of the two, not their sum")
    }

    @Test("two separate stretches on one night both count")
    func disjointStretchesBothCount() {
        let night = [
            SleepInterval(start: date(10, 23), end: date(11, 2), stage: .core),
            SleepInterval(start: date(11, 3), end: date(11, 6), stage: .core),
        ]
        let breakdown = SleepAggregator.byWakeDay(night, calendar: calendar)[day(11)]

        #expect(breakdown?.asleepHours == 6)
    }
}

extension SleepAggregatorTests {
    @Test("Unspecified phone sleep overlapping watch stages counts once")
    func mixedSources() {
        let night = [
            SleepInterval(start: date(10, 23), end: date(11, 7), stage: .unspecified),
            SleepInterval(start: date(10, 23), end: date(11, 2), stage: .core),
            SleepInterval(start: date(11, 2), end: date(11, 4), stage: .deep),
            SleepInterval(start: date(11, 4), end: date(11, 7), stage: .rem),
        ]
        let value = SleepAggregator.byWakeDay(night, calendar: calendar)[day(11)]
        #expect(value?.asleepHours == 8)
        #expect(value?.coreHours == 3)
        #expect(value?.deepHours == 2)
        #expect(value?.remHours == 3)
    }
}

extension SleepAggregatorTests {
    @Test("Early stages and the total share the episode's wake day")
    func stageBeforeMidnight() {
        let samples = [
            SleepInterval(start: date(10, 22), end: date(10, 23), stage: .core),
            SleepInterval(start: date(10, 23), end: date(11, 1), stage: .deep),
            SleepInterval(start: date(11, 1), end: date(11, 6), stage: .rem),
        ]
        let result = SleepAggregator.byWakeDay(samples, calendar: calendar)
        #expect(result[day(10)] == nil)
        #expect(result[day(11)]?.coreHours == 1)
        #expect(result[day(11)]?.asleepHours == 8)
    }

    @Test("In-bed and awake alone do not record zero sleep")
    func unmeasuredSleep() {
        let samples = [SleepInterval(start: date(10, 22), end: date(11, 7), stage: .inBed)]
        let result = SleepAggregator.byWakeDay(samples, calendar: calendar)[day(11)]
        #expect(result?.inBedHours == 9)
        #expect(result?.recordedSleepHours == nil)
    }
}
