import Foundation
import Testing
@testable import ReadinessCore

@Suite("Recorded sleep score")
struct SleepScoreTests {
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

    @Test("Eight hours with recorded awakenings scores below eight consolidated hours")
    func equalDurationDifferentContinuity() throws {
        let consolidated = SleepScore.evaluate(breakdown: night(19), durationHours: 8)
        let fragmented = SleepScore.evaluate(breakdown: night(19, awake: 2), durationHours: 8)
        #expect(try #require(fragmented.percent) < #require(consolidated.percent))
        #expect(fragmented.continuityPercent == 80)
        #expect(fragmented.percent == 80)
    }

    @Test("Duration alone cannot claim sleep quality or a perfect sleep score")
    func durationOnly() {
        let result = SleepScore.evaluate(breakdown: nil, durationHours: 8)
        #expect(result.percent == nil)
        #expect(result.durationPercent == 100)
        #expect(result.continuityPercent == nil)
        #expect(result.coverage == .durationOnly)
    }

    @Test("Missing sleep and invalid numbers remain missing")
    func invalidDuration() {
        for value in [Double.nan, .infinity, -1, 0] {
            #expect(SleepScore.evaluate(breakdown: nil, durationHours: value).percent == nil)
        }
        #expect(SleepScore.evaluate(breakdown: nil, durationHours: nil).coverage == .missing)
    }

    @Test("Conflicting awake and asleep sources do not become reliable continuity")
    func conflictingSamples() {
        let samples = [
            SleepInterval(start: date(18, 23), end: date(19), stage: .core),
            SleepInterval(start: date(19, 2), end: date(19, 3), stage: .awake),
        ]
        let breakdown = SleepAggregator.byWakeDay(samples, calendar: calendar)[calendar.startOfDay(for: date(19))]
        #expect(SleepScore.evaluate(breakdown: breakdown, durationHours: 8).percent == nil)
    }

    @Test("Unobserved gaps between stage samples are not assumed asleep or awake")
    func missingIntervals() {
        let samples = [
            SleepInterval(start: date(18, 23), end: date(19, 2), stage: .core),
            SleepInterval(start: date(19, 3), end: date(19, 7), stage: .core),
        ]
        let breakdown = SleepAggregator.byWakeDay(samples, calendar: calendar)[calendar.startOfDay(for: date(19))]
        #expect(SleepScore.evaluate(breakdown: breakdown, durationHours: 7).percent == nil)
    }

    @Test("A trustworthy in-bed window also establishes recorded efficiency")
    func inBedEfficiency() {
        let samples = [
            SleepInterval(start: date(18, 21), end: date(19, 7), stage: .inBed),
            SleepInterval(start: date(18, 23), end: date(19, 7), stage: .unspecified),
        ]
        let breakdown = SleepAggregator.byWakeDay(samples, calendar: calendar)[calendar.startOfDay(for: date(19))]
        #expect(SleepScore.evaluate(breakdown: breakdown, durationHours: 8).continuityPercent == 80)
    }

    @Test("A week of observed schedules can reduce a shifted night's heuristic")
    func regularityUsesActualTimes() throws {
        let history = (11...17).map { night($0) }
        let stable = SleepScore.evaluate(breakdown: night(19), durationHours: 8, history: history, calendar: calendar)
        var shifted = night(19)
        shifted.primarySleepStart = shifted.primarySleepStart?.addingTimeInterval(2 * 3600)
        shifted.primarySleepEnd = shifted.primarySleepEnd?.addingTimeInterval(2 * 3600)
        let irregular = SleepScore.evaluate(breakdown: shifted, durationHours: 8, history: history, calendar: calendar)
        #expect(try #require(irregular.percent) < #require(stable.percent))
        #expect(stable.baselineNights == 7)
        #expect(SleepScore.evaluate(breakdown: night(19), durationHours: 8, history: Array(history.prefix(6)), calendar: calendar).regularityPercent == nil)
    }

    @Test("Schedule baseline excludes today future stale and duplicate nights")
    func scheduleBoundaries() {
        let history = [night(19), night(20)] + Array(repeating: night(18), count: 8)
        let result = SleepScore.evaluate(breakdown: night(19), durationHours: 8, history: history, calendar: calendar)
        #expect(result.baselineNights == 1)
        #expect(result.regularityPercent == nil)
    }

    @Test("Long durations and invalid targets cannot overflow the score")
    func bounds() throws {
        let value = SleepScore.evaluate(breakdown: night(19), durationHours: 24)
        #expect(try #require(value.percent) <= 100)
        #expect(SleepScore.evaluate(breakdown: night(19), durationHours: 8, targetHours: 0).percent == nil)
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
        #expect(StrainEngine.acwr(daily: Array(repeating: 1000, count: 28)) == 1)
        #expect(StrainEngine.acwr(daily: Array(repeating: 0, count: 27) + [1000]) == nil)
    }
}
