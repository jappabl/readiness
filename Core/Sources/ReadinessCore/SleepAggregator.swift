import Foundation

/// What a sleep sample says the body was doing. Mirrors what HealthKit records, kept
/// free of HealthKit so the aggregation can be tested without a store.
public enum SleepStage: String, Sendable, Equatable, CaseIterable, Codable {
    case inBed
    case awake
    case unspecified
    case core
    case deep
    case rem

    /// In bed is not asleep, and neither is lying there awake at four in the morning.
    public var isAsleep: Bool {
        switch self {
        case .unspecified, .core, .deep, .rem: return true
        case .inBed, .awake: return false
        }
    }
}

public struct SleepInterval: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let stage: SleepStage

    public init(start: Date, end: Date, stage: SleepStage) {
        self.start = start
        self.end = end
        self.stage = stage
    }

    var hours: Double { max(0, end.timeIntervalSince(start)) / 3600 }
}

public struct SleepBreakdown: Sendable, Equatable {
    public var asleepHours: Double = 0
    public var coreHours: Double = 0
    public var deepHours: Double = 0
    public var remHours: Double = 0
    public var awakeHours: Double = 0
    public var inBedHours: Double = 0

    public init() {}

    /// How much of the time in bed was actually spent asleep. Nil rather than 1.0 when
    /// nothing recorded time in bed, because a watch-only night genuinely does not know.
    public var efficiency: Double? {
        guard inBedHours > 0 else { return nil }
        return min(1, asleepHours / inBedHours)
    }
}

public enum SleepAggregator {

    /// A night's sleep belongs to the day you woke up on, which is the day you have to
    /// train on.
    ///
    /// Overlapping samples are merged rather than summed. A phone and a watch both
    /// recording the same night is the normal case, not an edge case, and adding them
    /// together reports fourteen hours of sleep to someone who got seven.
    public static func byWakeDay(_ intervals: [SleepInterval],
                                 calendar: Calendar = .current) -> [Date: SleepBreakdown] {
        var out: [Date: SleepBreakdown] = [:]

        for stage in SleepStage.allCases {
            let merged = union(intervals.filter { $0.stage == stage })
            for interval in merged {
                let wakeDay = calendar.startOfDay(for: interval.end)
                var breakdown = out[wakeDay] ?? SleepBreakdown()
                switch stage {
                case .core:         breakdown.coreHours += interval.hours
                case .deep:         breakdown.deepHours += interval.hours
                case .rem:          breakdown.remHours += interval.hours
                case .awake:        breakdown.awakeHours += interval.hours
                case .inBed:        breakdown.inBedHours += interval.hours
                case .unspecified:  break
                }
                if stage.isAsleep { breakdown.asleepHours += interval.hours }
                out[wakeDay] = breakdown
            }
        }
        return out
    }

    /// Merges overlapping and touching intervals into the smallest set covering the
    /// same time.
    static func union(_ intervals: [SleepInterval]) -> [SleepInterval] {
        let sorted = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard var current = sorted.first else { return [] }

        var merged: [SleepInterval] = []
        for interval in sorted.dropFirst() {
            if interval.start <= current.end {
                guard interval.end > current.end else { continue }
                current = SleepInterval(start: current.start, end: interval.end, stage: current.stage)
            } else {
                merged.append(current)
                current = interval
            }
        }
        merged.append(current)
        return merged
    }
}
