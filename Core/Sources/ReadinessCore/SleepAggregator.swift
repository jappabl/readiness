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

    /// Every stretch of this wake day the person was asleep for, merged and in order.
    ///
    /// `byWakeDay` already unions these to total the night; it used to discard them. They
    /// are what the strain wear check needs: a single wake instant cannot say that the
    /// afternoon contained a nap, so time asleep was counted as time unrecorded.
    public var asleepPeriods: [DateInterval] = []

    public init() {}

    /// Asleep hours that nothing gave a stage to.
    ///
    /// Counted as light sleep rather than scaled into deep and REM. That is the one
    /// direction this can be wrong in without inventing anything: a stage says it
    /// happened, and an hour nobody labelled is not evidence of deep sleep.
    public var unlabelledHours: Double { max(0, asleepHours - stagedHours) }


    /// Hours that carry a stage. May exceed `asleepHours` when two devices each union
    /// their own samples and the totals are then summed.
    public var stagedHours: Double { deepHours + remHours + coreHours }

    /// The staged hours mapped onto the night that actually held them.
    ///
    /// Scaled down, never up. Two sources that between them label more of the night
    /// than it held are a proportional error and are reconciled to fit. A night nobody
    /// finished labelling keeps exactly the deep and REM that were recorded, and the
    /// hours that carry no label become light sleep.
    ///
    /// There used to be a floor under this: below 97%, later 85%, of the night, no
    /// breakdown at all. The reasoning was that the unlabelled part of a night is a
    /// contiguous window rather than a sample, so stretching the labelled part to fill
    /// it invents deep sleep that did not happen, which it measurably did. Giving the
    /// remainder to light fixes that at the root instead of withholding the night: deep
    /// and REM can now only ever be hours something actually recorded, so there is
    /// nothing left for a floor to protect, and a sleeper whose watch stopped early gets
    /// to see the night it did record.
    ///
    /// Nil only when nothing staged any of it, which is a different thing to say.
    public var reconciledStages: (deep: Double, rem: Double, core: Double)? {
        guard asleepHours > 0, stagedHours > 0 else { return nil }
        guard stagedHours > asleepHours else {
            return (deepHours, remHours, asleepHours - deepHours - remHours)
        }
        let scale = asleepHours / stagedHours
        return (deepHours * scale, remHours * scale, coreHours * scale)
    }

    /// A sleep starting before this hour is one the day began with.
    ///
    /// Nine, not six. Six is a bedtime, not a boundary: a night shift ending at 06:00, a
    /// new parent, anyone off a red-eye went to bed at exactly the hour that stopped
    /// qualifying, so a perfectly recorded day was reported as part-recorded every single
    /// day. Nine still excludes an afternoon sleep, which is the case the rule exists for.
    ///
    /// Not a length. Round 7 guarded the wake time by episode length: trust it only for
    /// four hours or more, and length cannot tell a night from a nap: a broken 3.5-hour
    /// night is a night, and a 4.5-hour afternoon sleep is not. That guard was wrong in
    /// both directions at once, hiding a 42-point hole after a short night and a 45-point
    /// one after a long daytime sleep. When the sleep started is the thing that actually
    /// separates them.
    public static let latestWakingStartHour = 9.0

    /// When the waking day began, or nil when the record cannot say.
    ///
    /// Not `primarySleepEnd`, which is the end of the longest asleep episode of the wake
    /// day: a wake time only when that episode was a night. With no night recorded, which
    /// is the watch-on-the-charger case and exactly the population this matters for, a
    /// recorded nap becomes the longest episode and this would hand back the middle of the
    /// afternoon. The strain wear check judges the day against a window starting here, so
    /// that put the window after the session it had missed: measured, a hard morning the
    /// watch never saw scored 22.5 against a true 73.0 and reported a complete record.
    ///
    /// A short or broken night is not trusted either. The fallback is a bound the clock can
    /// prove, which is weaker but never points at the wrong hour.
    /// The episode the night's own start and end describe, spanning any awake bridges.
    public var primarySleep: DateInterval? {
        guard let start = primarySleepStart, let end = primarySleepEnd, end > start
        else { return nil }
        return DateInterval(start: start, end: end)
    }

    public func wakeTime(on day: Date, calendar: Calendar = .current) -> Date? {
        WakingDay.start(of: asleepPeriods, primary: primarySleep, on: day, calendar: calendar)
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

/// When a day's waking hours began, read off the sleep that ended them.
///
/// Shared, because the strain engine and the app both have to agree about it. They did
/// not: one cut the day's primary sleep out of the heart-rate trace while the other only
/// trusted an episode it considered long enough to be a night, so an episode the second
/// rejected was removed from the trace by the first and then counted as a hole in it.
public enum WakingDay {

    /// The sleep the day began with: the earliest one that either ran in from yesterday
    /// or started in the small hours. A sleep that began in the afternoon says nothing
    /// about when the day started, however long it lasted.
    /// `day` is any moment inside the waking day being asked about.
    ///
    /// Taken from the caller rather than inferred from the periods. Inferring it from
    /// where the *first* period ended was wrong for any night that stirs: a staged night
    /// fragments at every awake segment, so a blip before local midnight put the inferred
    /// day a day early, nothing could qualify, and the answer went nil: switching the
    /// leading-gap check off and hiding fifty points, decided by which side of midnight
    /// somebody happened to turn over.
    public static func start(of periods: [DateInterval], primary: DateInterval?,
                             on day: Date, calendar: Calendar = .current) -> Date? {
        let dayStart = calendar.startOfDay(for: day)
        func qualifies(_ period: DateInterval) -> Bool {
            // A clock hour, not elapsed seconds: on the two days a year the clocks change
            // an elapsed-time test moves the cutoff by an hour. Same class as the bug that
            // made a day's last instant land in the next day.
            period.start < dayStart
                || calendar.component(.hour, from: period.start)
                    < Int(SleepBreakdown.latestWakingStartHour)
        }
        // The night's own episode, when the night itself qualifies. `periods` are
        // fragments (a staged night splits at every awake segment) so neither end of the
        // fragment list is reliably the moment the day began. Taking the first was wrong
        // (a five-minute misread, or ninety minutes awake mid-night, started the window
        // there and called the rest of the night a hole). Taking the last was wrong the
        // other way: any second sleep before nine dragged the start to *its* end, so a
        // hard morning between waking and a lie-down was never examined at all, and
        // because a wake time was found, the clock floor switched off too. The primary
        // episode spans its own awake bridges, which is exactly what neither end of the
        // fragment list does.
        if let primary, qualifies(primary) { return primary.end }
        return periods.filter(qualifies).map(\.end).max()
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
                breakdown.asleepPeriods.append(
                    contentsOf: asleep.map { DateInterval(start: $0.start, end: $0.end) })
                breakdown.asleepPeriods.sort { $0.start < $1.start }
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
