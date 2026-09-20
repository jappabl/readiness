import Foundation

public enum SleepScoreCoverage: Sendable, Equatable {
    case missing, durationOnly, durationAndContinuity, durationContinuityAndSchedule
}

public struct SleepScoreResult: Sendable, Equatable {
    public let percent: Int?
    public let durationPercent: Int?
    public let continuityPercent: Int?
    public let regularityPercent: Int?
    public let baselineNights: Int
    public let coverage: SleepScoreCoverage

    public var summary: String {
        guard let durationPercent else { return "No sleep duration recorded for last night." }
        guard percent != nil, let continuityPercent else {
            return "\(durationPercent)% of the duration target recorded. Sleep continuity is unavailable, so hours alone do not produce a sleep score."
        }
        let schedule = regularityPercent == nil
            ? "Schedule regularity is not included yet."
            : "Schedule consistency uses \(baselineNights) prior nights."
        return "\(durationPercent)% of the duration target, with \(continuityPercent)% recorded sleep continuity. \(schedule) This is a simple estimate, not a validated sleep-quality measure."
    }
}

/// A transparent descriptive heuristic, not a clinical sleep-quality score:
/// target-duration coverage × observed sleep continuity. If at least seven prior
/// nights have valid timestamps, schedule consistency can reduce the result by at
/// most 10%. Weights and the two-hour scale are product choices, not medical cutoffs.
/// Duration alone cannot establish sleep quality: https://www.cdc.gov/sleep/about/
public enum SleepScore {
    public static func evaluate(breakdown: SleepBreakdown?, durationHours: Double?,
                                history: [SleepBreakdown] = [], targetHours: Double = 8,
                                calendar: Calendar = .current) -> SleepScoreResult {
        let hours = durationHours ?? breakdown?.recordedSleepHours
        guard let hours, hours.isFinite, hours > 0,
              targetHours.isFinite, targetHours > 0 else {
            return .init(percent: nil, durationPercent: nil, continuityPercent: nil,
                         regularityPercent: nil, baselineNights: 0, coverage: .missing)
        }
        let duration = min(1, hours / targetHours)
        let durationPercent = Int((duration * 100).rounded())
        guard let continuity = breakdown?.recordedContinuity,
              continuity.isFinite, (0...1).contains(continuity) else {
            return .init(percent: nil, durationPercent: durationPercent, continuityPercent: nil,
                         regularityPercent: nil, baselineNights: 0, coverage: .durationOnly)
        }
        let schedule = regularity(breakdown: breakdown, history: history, calendar: calendar)
        let adjustment = schedule.fraction.map { 0.9 + 0.1 * $0 } ?? 1
        let score = min(100, max(0, Int((100 * duration * continuity * adjustment).rounded())))
        return .init(percent: score, durationPercent: durationPercent,
                     continuityPercent: Int((continuity * 100).rounded()),
                     regularityPercent: schedule.fraction.map { Int(($0 * 100).rounded()) },
                     baselineNights: schedule.count,
                     coverage: schedule.fraction == nil ? .durationAndContinuity : .durationContinuityAndSchedule)
    }

    private static func regularity(breakdown: SleepBreakdown?, history: [SleepBreakdown],
                                   calendar: Calendar) -> (fraction: Double?, count: Int) {
        guard let current = breakdown, let start = current.primarySleepStart,
              let end = current.primarySleepEnd, end > start,
              let cutoff = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: end)) else {
            return (nil, 0)
        }
        let today = calendar.startOfDay(for: end)
        var prior: [Date: SleepBreakdown] = [:]
        for night in history {
            guard let sleepStart = night.primarySleepStart, let sleepEnd = night.primarySleepEnd,
                  sleepEnd > sleepStart else { continue }
            let day = calendar.startOfDay(for: sleepEnd)
            guard day < today, day >= cutoff else { continue }
            prior[day] = night
        }
        guard prior.count >= 7 else { return (nil, prior.count) }
        let differences = prior.values.compactMap { night -> Double? in
            guard let otherStart = night.primarySleepStart, let otherEnd = night.primarySleepEnd else { return nil }
            return (clockDistance(start, otherStart, calendar: calendar)
                    + clockDistance(end, otherEnd, calendar: calendar)) / 2
        }.sorted()
        let middle = differences.count / 2
        let median = differences.count.isMultiple(of: 2)
            ? (differences[middle - 1] + differences[middle]) / 2 : differences[middle]
        return (max(0, 1 - median / 120), prior.count)
    }

    private static func clockDistance(_ first: Date, _ second: Date, calendar: Calendar) -> Double {
        func minutes(_ date: Date) -> Double {
            let components = calendar.dateComponents([.hour, .minute], from: date)
            return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        }
        let difference = abs(minutes(first) - minutes(second))
        return min(difference, 1440 - difference)
    }
}
