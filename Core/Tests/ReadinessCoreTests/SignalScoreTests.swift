import Foundation
import Testing
@testable import ReadinessCore

/// What the sleep engine reads out of real HealthKit-shaped samples: continuity, and
/// the schedule baseline. The score's own arithmetic — need, debt, quality, the
/// breakdown — lives in SleepNeedTests.swift.
///
/// These were written against `SleepScore.evaluate`, which returned a percent built from
/// duration times continuity times schedule. That engine has been replaced by one that
/// scores the night against a computed need. The cases below survived because they are
/// about reading samples honestly, which did not change: an unobserved gap is still not
/// sleep, and conflicting sources still do not add up to a confident number.
@Suite("Sleep, read from samples")
struct SleepSampleTests {
    var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    func date(_ day: Int, _ hour: Int = 7) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }
    func night(_ day: Int, awake: Double = 0) -> SleepBreakdown {
        let end = date(day)
        let start = end.addingTimeInterval(-(8 + awake) * 3600)
        let samples = [
            SleepInterval(start: start, end: start.addingTimeInterval(4 * 3600), stage: .core),
            SleepInterval(start: start.addingTimeInterval(4 * 3600), end: start.addingTimeInterval((4 + awake) * 3600), stage: .awake),
            SleepInterval(start: start.addingTimeInterval((4 + awake) * 3600), end: end, stage: .rem),
        ]
        return SleepAggregator.byWakeDay(samples, calendar: calendar)[calendar.startOfDay(for: end)]!
    }
    func score(_ breakdown: SleepBreakdown?, hours: Double?,
               history: [SleepBreakdown] = []) -> SignalScore {
        SleepScore.of(SleepInput(breakdown: breakdown, durationHours: hours,
                                 history: history,
                                 calendar: calendar))
    }
    func continuity(_ result: SignalScore) -> Double? {
        result.contributors.first { $0.id == "continuity" }?.value
    }

    @Test("Eight hours with recorded awakenings scores below eight consolidated hours")
    func equalDurationDifferentContinuity() throws {
        let consolidated = score(night(19), hours: 8)
        let fragmented = score(night(19, awake: 2), hours: 8)
        #expect(try #require(fragmented.value) < #require(consolidated.value))
        #expect(continuity(fragmented) == 80)
    }

    @Test("Conflicting awake and asleep sources do not become reliable continuity")
    func conflictingSamples() {
        let samples = [
            SleepInterval(start: date(18, 23), end: date(19), stage: .core),
            SleepInterval(start: date(19, 2), end: date(19, 3), stage: .awake),
        ]
        let breakdown = SleepAggregator.byWakeDay(samples, calendar: calendar)[calendar.startOfDay(for: date(19))]
        let result = score(breakdown, hours: 8)
        #expect(continuity(result) == nil)
        #expect(result.missing.contains { $0.localizedCaseInsensitiveContains("continuity") })
    }

    @Test("Unobserved gaps between stage samples are not assumed asleep or awake")
    func missingIntervals() {
        let samples = [
            SleepInterval(start: date(18, 23), end: date(19, 2), stage: .core),
            SleepInterval(start: date(19, 3), end: date(19, 7), stage: .core),
        ]
        let breakdown = SleepAggregator.byWakeDay(samples, calendar: calendar)[calendar.startOfDay(for: date(19))]
        #expect(continuity(score(breakdown, hours: 7)) == nil)
    }

    @Test("A trustworthy in-bed window also establishes recorded efficiency")
    func inBedEfficiency() {
        let samples = [
            SleepInterval(start: date(18, 21), end: date(19, 7), stage: .inBed),
            SleepInterval(start: date(18, 23), end: date(19, 7), stage: .unspecified),
        ]
        let breakdown = SleepAggregator.byWakeDay(samples, calendar: calendar)[calendar.startOfDay(for: date(19))]
        #expect(continuity(score(breakdown, hours: 8)) == 80)
    }

    @Test("A week of observed schedules can reduce a shifted night's score")
    func regularityUsesActualTimes() throws {
        let history = (11...17).map { night($0) }
        let stable = score(night(19), hours: 8, history: history)
        var shifted = night(19)
        shifted.primarySleepStart = shifted.primarySleepStart?.addingTimeInterval(2 * 3600)
        shifted.primarySleepEnd = shifted.primarySleepEnd?.addingTimeInterval(2 * 3600)
        let irregular = score(shifted, hours: 8, history: history)
        #expect(try #require(irregular.value) < #require(stable.value))
        #expect(stable.contributors.contains { $0.id == "schedule" })
        #expect(!score(night(19), hours: 8, history: Array(history.prefix(6)))
            .contributors.contains { $0.id == "schedule" })
    }

    @Test("Schedule baseline excludes today future stale and duplicate nights")
    func scheduleBoundaries() {
        let history = [night(19), night(20)] + Array(repeating: night(18), count: 8)
        let result = score(night(19), hours: 8, history: history)
        #expect(!result.contributors.contains { $0.id == "schedule" },
                "one distinct prior night is not a schedule baseline")
    }
}

@Suite("Daily recorded activity strain")
struct DailyStrainTests {
    var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }
    var history: [DailyActivity] {
        (11...17).map { DailyActivity(date: date($0), activeEnergyKcal: 400) }
    }

    @Test("Current activity is usable without any in-app workout logs")
    func healthActivityWorks() {
        let value = DailyStrain.evaluate(days: history + [.init(date: date(19), activeEnergyKcal: 500)], on: date(19), calendar: calendar)
        #expect(value?.percent == 100)
        #expect(value?.metric == .activeEnergy)
        #expect(value?.baselineDays == 7)
    }

    @Test("A normal full day's activity sits in the middle of identical past days")
    func tiesUseMidrank() {
        let value = DailyStrain.evaluate(days: history + [.init(date: date(19), activeEnergyKcal: 400)], on: date(19), calendar: calendar)
        #expect(value?.percent == 50)
    }

    @Test("Recorded zero differs from missing even while history is building")
    func zeroAndMissing() {
        #expect(DailyStrain.evaluate(days: [.init(date: date(19), activeEnergyKcal: 0)], on: date(19), calendar: calendar)?.percent == 0)
        #expect(DailyStrain.evaluate(days: [.init(date: date(19))], on: date(19), calendar: calendar) == nil)
    }

    @Test("Sparse history preserves raw activity without inventing a percentile")
    func noBaseline() {
        let value = DailyStrain.evaluate(days: [.init(date: date(19), activeEnergyKcal: 500)], on: date(19), calendar: calendar)
        #expect(value?.value == 500)
        #expect(value?.percent == nil)
        #expect(value?.baselineDays == 0)
    }

    @Test("Workout energy is never added to a daily active-energy total")
    func noDoubleCount() {
        let value = DailyStrain.evaluate(days: history + [.init(date: date(19), activeEnergyKcal: 400, workoutEnergyKcal: 300)], on: date(19), calendar: calendar)
        #expect(value?.value == 400)
        #expect(value?.percent == 50)
    }

    @Test("Workout-only coverage is labeled and retains its own metric history")
    func workoutFallback() {
        let days = (11...17).map { DailyActivity(date: date($0), workoutEnergyKcal: 200) }
        let value = DailyStrain.evaluate(days: days + [.init(date: date(19), workoutEnergyKcal: 100)], on: date(19), calendar: calendar)
        #expect(value?.metric == .workoutEnergy)
        #expect(value?.percent == 0)
    }

    @Test("Steps provide a same-source fallback when energy is not shared")
    func stepsFallback() {
        let days = (11...17).map { DailyActivity(date: date($0), steps: 5000) }
        let value = DailyStrain.evaluate(days: days + [.init(date: date(19), steps: 5000)], on: date(19), calendar: calendar)
        #expect(value?.metric == .steps)
        #expect(value?.percent == 50)
    }

    @Test("Today must exist and future or stale records cannot supply the baseline")
    func dayBoundaries() {
        #expect(DailyStrain.evaluate(days: history, on: date(19), calendar: calendar) == nil)
        let days = history.prefix(5) + [.init(date: date(20), activeEnergyKcal: 400), .init(date: date(19), activeEnergyKcal: 500), .init(date: date(19, hour: 18), activeEnergyKcal: 600), .init(date: date(-12), activeEnergyKcal: 400)]
        let value = DailyStrain.evaluate(days: Array(days), on: date(19, hour: 20), calendar: calendar)
        #expect(value?.baselineDays == 5)
        #expect(value?.value == 600)
        #expect(value?.percent == nil)
    }

    @Test("Duplicate dates do not fake a seven-day baseline")
    func duplicateDays() {
        let days = Array(repeating: DailyActivity(date: date(18), activeEnergyKcal: 400), count: 7) + [.init(date: date(19), activeEnergyKcal: 500)]
        #expect(DailyStrain.evaluate(days: days, on: date(19), calendar: calendar)?.baselineDays == 1)
    }

    @Test("Invalid values are missing and finite outliers stay bounded")
    func numericBounds() throws {
        for invalid in [Double.nan, .infinity, -5] {
            #expect(DailyStrain.evaluate(days: [.init(date: date(19), activeEnergyKcal: invalid)], on: date(19), calendar: calendar) == nil)
        }
        let value = DailyStrain.evaluate(days: history + [.init(date: date(19), activeEnergyKcal: 1e100)], on: date(19), calendar: calendar)
        #expect(try #require(value?.percent) <= 100)
    }

    @Test("Daily strain work does not change strength ACWR behavior")
    func acwrUnaffected() {
        #expect(StrainEngine.acwr(daily: Array(repeating: 1000, count: 28),
                                  observedDays: 28) == 1)
        #expect(StrainEngine.acwr(daily: Array(repeating: 0, count: 27) + [1000],
                                  observedDays: 28) == nil)
    }
}
