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

    /// Available only when interval coverage establishes continuity without conflicting
    /// awake/asleep samples. Nil means unknown, not perfectly consolidated sleep.
    public var recordedContinuity: Double?
    public var primarySleepStart: Date?
    public var primarySleepEnd: Date?

    public init() {}

    /// How much of the night has to carry a stage before the record is describing its
    /// structure at all.
    ///
    /// A night can be recorded as asleep without being classified — an `unspecified` run
    /// from a second source, or a watch that only staged part of it. Asking merely whether
    /// *any* stage was recorded made one labelled sample stand for the whole night and
    /// charged every unclassified hour to the stages as a zero, so the app named a stage
    /// the device never classified as the night's worst component. That is verbatim the
    /// failure this predicate exists to prevent, arriving from the other side.
    public static let minimumStagedShare = 0.75

    /// Hours that carry a stage. May exceed `asleepHours` when two devices each union
    /// their own samples and the totals are then summed.
    public var stagedHours: Double { deepHours + remHours + coreHours }

    /// The staged hours mapped onto the night that actually held them, or nil when too
    /// little of it was classified to say what it was made of.
    ///
    /// One scale, both directions. Two devices over-count and are scaled down; a partly
    /// classified night is scaled up, which assumes the unlabelled part looked like the
    /// labelled part — a stated assumption, and a far better one than charging it to the
    /// stages as zeros, which made measuring *less* of a night score it *higher*.
    public var reconciledStages: (deep: Double, rem: Double, core: Double)? {
        guard asleepHours > 0, stagedHours > 0,
              stagedHours >= asleepHours * Self.minimumStagedShare else { return nil }
        let scale = asleepHours / stagedHours
        return (deepHours * scale, remHours * scale, coreHours * scale)
    }

    /// Shorter than this and the longest episode of the day was a nap, not a night.
    public static let minimumNightHours = 4.0

    /// When the waking day began, or nil when the record cannot say.
    ///
    /// Not `primarySleepEnd`, which is the end of the longest asleep episode of the wake
    /// day — a wake time only when that episode was a night. With no night recorded, which
    /// is the watch-on-the-charger case and exactly the population this matters for, a
    /// recorded nap becomes the longest episode and this would hand back the middle of the
    /// afternoon. The strain wear check judges the day against a window starting here, so
    /// that put the window after the session it had missed: measured, a hard morning the
    /// watch never saw scored 22.5 against a true 73.0 and reported a complete record.
    ///
    /// A short or broken night is not trusted either. The fallback is a bound the clock can
    /// prove, which is weaker but never points at the wrong hour.
    public var wakeTime: Date? {
        guard let start = primarySleepStart, let end = primarySleepEnd,
              end.timeIntervalSince(start) >= Self.minimumNightHours * 3600
        else { return nil }
        return end
    }

    /// In-bed or awake records alone do not establish how long someone slept.
    public var recordedSleepHours: Double? { asleepHours > 0 ? asleepHours : nil }

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
        var primaryHours: [Date: Double] = [:]

        let valid = intervals.filter { $0.end > $0.start }
        // Connected intervals form one sleep episode, including awake/in-bed bridges.
        // Assign every stage and the total to the same episode's wake day.
        for episode in union(valid) {
            let samples = valid.filter { $0.start < episode.end && $0.end > episode.start }
            let wakeDay = calendar.startOfDay(for: episode.end)
            var breakdown = out[wakeDay] ?? SleepBreakdown()
            for stage in SleepStage.allCases {
                let hours = union(samples.filter { $0.stage == stage }).reduce(0) { $0 + $1.hours }
                switch stage {
                case .core: breakdown.coreHours += hours
                case .deep: breakdown.deepHours += hours
                case .rem: breakdown.remHours += hours
                case .awake: breakdown.awakeHours += hours
                case .inBed: breakdown.inBedHours += hours
                case .unspecified: break
                }
            }
            // Unspecified phone sleep can overlap watch stages; count that time once.
            let asleep = union(samples.filter { $0.stage.isAsleep })
            let episodeHours = asleep.reduce(0) { $0 + $1.hours }
            if episodeHours > 0 {
                // Multiple disconnected sleep episodes cannot establish the continuity
                // between them. Keep the duration, but do not silently fill the gaps.
                breakdown.recordedContinuity = breakdown.asleepHours == 0
                    ? continuity(samples: samples, asleep: asleep) : nil
                if episodeHours > (primaryHours[wakeDay] ?? 0) {
                    breakdown.primarySleepStart = asleep.first?.start
                    breakdown.primarySleepEnd = asleep.last?.end
                    primaryHours[wakeDay] = episodeHours
                }
            }
            breakdown.asleepHours += episodeHours
            out[wakeDay] = breakdown
        }
        return out
    }

    private static func continuity(samples: [SleepInterval], asleep: [SleepInterval]) -> Double? {
        guard let start = asleep.first?.start, let end = asleep.last?.end else { return nil }
        let awake = union(samples.filter { $0.stage == .awake })
        // Multiple devices may disagree. A conflicting overlap is not a reliable
        // measure of either awake time or efficiency.
        guard !awake.contains(where: { wake in
            asleep.contains { sleep in wake.start < sleep.end && wake.end > sleep.start }
        }) else { return nil }
        let asleepHours = asleep.reduce(0) { $0 + $1.hours }
        let inBed = union(samples.filter { $0.stage == .inBed })
        if !inBed.isEmpty {
            let fullyContained = asleep.allSatisfy { sleep in
                inBed.contains { $0.start <= sleep.start && $0.end >= sleep.end }
            }
            if fullyContained {
                let hours = inBed.reduce(0) { $0 + $1.hours }
                return hours >= asleepHours ? asleepHours / hours : nil
            }
        }
        // Apple Watch awake records cover time between sleep samples, not latency
        // before sleep or time awake after the last sample. Report recorded continuity.
        let detailed = samples.filter { $0.stage == .core || $0.stage == .deep || $0.stage == .rem }
        let detailedHours = union(detailed).reduce(0) { $0 + $1.hours }
        guard abs(detailedHours - asleepHours) < 0.0001 else { return nil }
        let observed = union(detailed + awake)
        guard observed.contains(where: { $0.start <= start && $0.end >= end }) else { return nil }
        return min(1, asleepHours / (end.timeIntervalSince(start) / 3600))
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
