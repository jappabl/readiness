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
