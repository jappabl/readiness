import Foundation

/// One bucket of time at one heart rate, with `minutes` being how long that reading
/// stood for: the gap to the next one, capped. Not raw beats.
public struct HeartRateSample: Sendable, Equatable {
    public let start: Date
    public let minutes: Double
    public let beatsPerMinute: Double

    public init(start: Date, minutes: Double, beatsPerMinute: Double) {
        self.start = start
        self.minutes = minutes
        self.beatsPerMinute = beatsPerMinute
    }

    var isUsable: Bool {
        minutes.isFinite && minutes > 0 && beatsPerMinute.isFinite && beatsPerMinute > 0
    }
}

public struct StrainInput: Sendable {
    public let samples: [HeartRateSample]
    /// The baseline, not this morning's reading: a bad night should not inflate the
    /// whole day's load by moving the bottom of the reserve.
    public let restingHeartRate: Double?
    public let ageYears: Int?
    public let biologicalSex: HealthProfile.BiologicalSex?
    /// The highest heart rate this person has actually been seen at, if higher than the
    /// formula predicts. A population average loses to a measurement.
    public let observedMaxHeartRate: Double?
    public let hardSets: Int
    /// When the day is being read. The wear check needs a clock: a trace covering two
    /// hours is a complete record at nine in the morning and a third of a record at six
    /// in the evening, and without one the span test had nothing to compare against.
    public let readAt: Date

    /// Every stretch of the day spent asleep, so time in bed is not read as time the
    /// watch was off. Without it a nap was a hole and a night the day started with was
    /// the only sleep the check could reason about at all.
    public let asleepPeriods: [DateInterval]

    /// The episode the day began from, spanning its own awake bridges. See
    /// `WakingDay.start(of:primary:on:)`: the fragment list alone cannot say.
    public let primarySleep: DateInterval?
    /// What the ring showed before this engine existed. Used only when there is no
    /// cardiac trace at all, and always labelled.
    public let fallback: DailyStrainResult?

    public init(samples: [HeartRateSample], restingHeartRate: Double?, ageYears: Int?,
                biologicalSex: HealthProfile.BiologicalSex?,
                observedMaxHeartRate: Double? = nil, hardSets: Int = 0,
                readAt: Date = Date(), asleepPeriods: [DateInterval] = [],
                primarySleep: DateInterval? = nil,
                fallback: DailyStrainResult? = nil) {
        self.samples = samples
        self.restingHeartRate = restingHeartRate
        self.ageYears = ageYears
        self.biologicalSex = biologicalSex
        self.observedMaxHeartRate = observedMaxHeartRate
        self.hardSets = hardSets
        self.readAt = readAt
        self.asleepPeriods = asleepPeriods
        self.primarySleep = primarySleep
        self.fallback = fallback
    }
}

/// How hard today was, on a 0...21 scale.
///
/// The scale is Whoop's and is derived from Borg's 6...20 rating of perceived exertion,
/// stretched by a point to leave room at the top. What sits underneath it here is
/// Banister's TRIMP, which is published, forty years old and testable: the app does not
/// need a proprietary load model to say something true about a day.
///
/// The constants are absolute and stated. The known cost is that an untrained person
/// sits low for months and a trained endurance athlete presses the ceiling; that is what
/// a fixed scale buys and what it charges.
///
/// See docs/superpowers/specs/2026-09-19-signal-scores-design.md.
public enum StrainScore {

    public static let modelVersion = "strain-v1.0.0"

    // MARK: - Maximum heart rate

    /// Tanaka rather than 220 minus age, which overestimates the young and
    /// underestimates the old. Every reserve fraction below rests on this number.
    public static func maximumHeartRate(ageYears: Int?, observed: Double? = nil) -> Double {
        let predicted = ageYears.map { 208 - 0.7 * Double($0) } ?? assumedMaximumHeartRate
        guard let observed, observed.isFinite, observed > predicted else { return predicted }
        // Bounded, because the observed maximum comes from HealthKit's raw daily peak
        // and a single bad beat weeks ago would otherwise widen the reserve forever:
        // quietly dropping every session since out of the band it belongs in.
        return Swift.min(observed, predicted + observedMaximumHeadroom)
    }

    /// How far above the formula a measured maximum is allowed to reach.
    public static let observedMaximumHeadroom = 15.0

    /// Used when there is no date of birth. Roughly a forty-year-old, so it is wrong in
    /// both directions rather than systematically wrong in one.
    public static let assumedMaximumHeartRate = 190.0

    /// Used when there is no resting heart rate yet. Deliberately unremarkable.
    public static let assumedRestingHeartRate = 60.0

    // MARK: - Banister TRIMP

    /// The coefficient is 0.64 for everyone; only the exponent differs by sex. Getting
    /// that backwards is the classic transcription error, so both are pinned by test.
    static let trimpCoefficient = 0.64
    static let maleExponent = 1.92
    static let femaleExponent = 1.67

    static func exponent(for sex: HealthProfile.BiologicalSex?) -> Double {
        switch sex {
        case .male: return maleExponent
        case .female: return femaleExponent
        // `other` and unknown both land between the two published curves rather than
        // silently picking one of them.
        case .other, nil: return (maleExponent + femaleExponent) / 2
        }
    }

    public static func trimp(minutes: Double, heartRate: Double, resting: Double,
                             maximum: Double, sex: HealthProfile.BiologicalSex?) -> Double {
        guard minutes.isFinite, minutes > 0, heartRate.isFinite,
              maximum > resting else { return 0 }
        // Below resting contributes nothing. Above maximum is clamped rather than
        // extrapolated: the curve is exponential and a bad sample would dominate a day.
        let reserve = min(max((heartRate - resting) / (maximum - resting), 0), 1)
        return minutes * reserve * trimpCoefficient * exp(exponent(for: sex) * reserve)
    }

    // MARK: - Muscular load

    /// A heavy triple barely moves an average heart rate, so lifting would be invisible
    /// to a purely cardiac measure.
    ///
    /// Was 2.0, which put twenty hard sets at the cost of half an hour's jogging and
    /// meant lifting alone could not leave the bottom band until about forty-three sets.
    /// At 5.0 one hard set is worth roughly two minutes near threshold, twenty sets
    /// reach "moderate", and a real session lands where a lifter would put it.
    public static let hardSetLoad = 5.0

    public static func muscularLoad(hardSets: Int) -> Double {
        Double(max(0, hardSets)) * hardSetLoad
    }

    // MARK: - The 0...21 map

    /// Curve shape. Smaller makes the bottom of the scale steeper.
    ///
    /// Was 40 against a 400 ceiling, which spent six of the twenty-one points below
    /// anything anybody would call training and let a three-hour easy ride read as all
    /// out. 20 against 650 keeps the bottom honest and buys back the top: a five-hour
    /// day for a fit athlete lands at 20 instead of slamming into the clamp, where a
    /// marathon and a double both read 21.
    public static let curveShape = 20.0
    /// The day's load that reads as a full 21.
    public static let ceilingLoad = 650.0
    /// Was 21, following Whoop, which takes it from Borg's 6-20 exertion scale. That is
    /// Whoop's branding rather than a physical constant, and a third ring on a different
    /// scale beside two percentages is a puzzle the reader has to solve every time. The
    /// curve underneath is unchanged; only its top is.
    public static let scaleMax = 100.0

    public static func strain(load: Double) -> Double {
        guard load.isFinite, load > 0 else { return 0 }
        let value = scaleMax * log(1 + load / curveShape) / log(1 + ceilingLoad / curveShape)
        return min(scaleMax, value)
    }

    /// The inverse, for reasoning about what a point on the scale costs.
    public static func load(strain: Double) -> Double {
        curveShape * (exp(strain / scaleMax * log(1 + ceilingLoad / curveShape)) - 1)
    }

    // MARK: - Zones

    /// Buckets of heart rate reserve. Zone 0 is everything under the first training
    /// zone, most of most days, and not nothing: it is where a long day on your feet
    /// shows up.
    public struct Zone: Sendable, Equatable {
        public let id: String
        public let title: String
        public let lowerReserve: Double
        public let symbol: String
    }

    public static let zones: [Zone] = [
        Zone(id: "zone5", title: "All-out effort", lowerReserve: 0.90, symbol: "flame.fill"),
        Zone(id: "zone4", title: "Hard effort", lowerReserve: 0.80, symbol: "figure.run"),
        Zone(id: "zone3", title: "Moderate effort", lowerReserve: 0.70, symbol: "figure.run"),
        Zone(id: "zone2", title: "Light effort", lowerReserve: 0.60, symbol: "figure.walk.motion"),
        // Starts at 0.40 rather than 0.50 so a brisk walk escapes the everyday bucket
        // and its cap. Nothing in a desk trace reaches 0.40, so this does not leak.
        Zone(id: "zone1", title: "Very light effort", lowerReserve: 0.40, symbol: "figure.walk.motion"),
        Zone(id: "zone0", title: "Everyday movement", lowerReserve: 0.0, symbol: "figure.walk"),
    ]

    /// How much load being awake saturates towards, before the training ramp.
    ///
    /// Not a hard ceiling on the everyday zone any more, and the distinction matters:
    /// the ramp begins at 0.30 reserve while zone 0 runs to 0.40, so buckets in between
    /// earn partial training credit that is filed under zone 0 and bypasses this.
    /// Sixteen hours sustained at 0.399 reserve is eight times this figure, not an
    /// ordinary day, but not what the old wording promised either.
    ///
    /// The bug this exists for: sixteen waking hours at an unremarkable 70 bpm is 87
    /// load, which on the old curve was a strain of 10 out of 21 ("moderate") for a
    /// person who did nothing at all. Fifteen hours of sitting outweighed a 45-minute
    /// run, so on a day somebody ran, the breakdown's top row was sitting down.
    ///
    /// Duration cannot be the answer below the first training zone: the cost per minute
    /// is real but tiny, and a day is 1440 of them. Capping it keeps a long day on your
    /// feet worth something without letting it become the day.
    public static let everydayLoadCap = 25.0

    /// Where a minute stops counting as pottering and starts counting as training.
    ///
    /// A hard cut at the zone boundary was a cliff: sixteen hours just under it saturated
    /// at the cap, and one beat per minute higher put every one of those minutes on the
    /// unbounded side: 104 bpm read 20, 105 bpm read 95. Ramping across a band means a
    /// bucket near the line contributes part of its load to each side, so the score moves
    /// smoothly with the day instead of hinging on it.
    public static let everydayRampLow = 0.30
    public static let everydayRampHigh = 0.55

    /// How much of a bucket counts as training rather than as being awake.
    static func trainingShare(reserve: Double) -> Double {
        let t = Swift.min(1, Swift.max(0, (reserve - everydayRampLow)
                                       / (everydayRampHigh - everydayRampLow)))
        return t * t * (3 - 2 * t)
    }

    /// Below this many minutes of heart rate, the day is a sample rather than a record.
    /// Half a day, because a watch charged overnight and worn from nine to nine is the
    /// normal case and should not be flagged.
    /// A contiguous unobserved stretch this long is a hole a session fits in.
    ///
    /// Forty minutes. Above a worn watch's own resting cadence, which drops to a reading
    /// every half hour when nothing is happening, and below the shortest thing anybody
    /// would call a session. An hour was too generous: a watch reading once an hour
    /// leaves fifty-five-minute holes and is not a record of a day.
    ///
    /// Deliberately an absolute length rather than a share of the day. A share was the
    /// bug: ninety minutes missing out of sixteen hours is a share of 0.91, so no
    /// threshold on a share separates it from a day that is simply complete.
    public static let unobservedGapMinutes = 40.0

    /// The most of a day anybody is taken to have slept, used only when the night itself
    /// is unknown.
    ///
    /// The waking day has no start whenever nothing the record calls sleep ended this
    /// morning: the watch charged overnight, sleep tracked on the phone alone, or
    /// sleep-analysis permission declined, and in that last case on every day,
    /// permanently. Falling back to the first sample is what made the wear check a
    /// tautology twice over, because a watch put on late produces a trace whose start IS
    /// the window start, so there is no leading gap left to find.
    ///
    /// Without a wake time there is no honest way to place the start of the waking day,
    /// and guessing at one flags people who simply opened the card in the morning. What
    /// can be said without guessing is a lower bound: however late they slept, by this
    /// hour at least `time since midnight - 10 h` of waking day has happened, and a trace
    /// shorter than that cannot be describing all of it. The bound is empty early in the
    /// day, which is exactly when nothing should be claimed, and tightens as the day runs
    /// on.
    ///
    /// Eleven hours rather than ten. At ten the bound reduced to "flag any complete day
    /// whose trace starts after 10:00", which catches a Saturday lie-in and, worse, anyone
    /// on a night shift, and the population this applies to is exactly the people with no
    /// sleep data, who are disproportionately the ones sleeping at odd hours. Eleven still
    /// fires on the case the floor exists for: a watch on the charger until noon, read at
    /// eleven at night, has 660 minutes of trace against 720 provably awake.
    ///
    /// It cannot be made to distinguish "woke late" from "put the watch on late", nothing
    /// can, without a night to read. Where it is wrong it adds a line saying how much was
    /// recorded, which is cheap; the error it is guarding against is a hard session read as
    /// a rest day, which is not.
    public static let maximumSleepMinutes = 660.0


    static func zone(forReserve reserve: Double) -> Zone {
        zones.first { reserve >= $0.lowerReserve } ?? zones[zones.count - 1]
    }

    public static let muscularContributorID = "muscular"

    // MARK: - Target

    /// What today is worth doing, given how recovered you are.
    ///
    /// Deliberately never stated in words anywhere: it is a tick on the ring. A target
    /// written as a sentence is an instruction, and a coach who issues a number every
    /// morning is a spreadsheet. As a mark you are heading towards it is a suggestion,
    /// and passing it is allowed.
    ///
    /// The floor matters as much as the slope: even a wrecked morning has a target above
    /// nothing, because doing nothing is rarely the right answer and a target of zero
    /// would say it is.
    public static let targetFloor = 30.0
    public static let targetCeiling = 85.0

    public static func target(recovery: Double?) -> Double? {
        guard let recovery, recovery.isFinite else { return nil }
        let share = Swift.min(1, Swift.max(0, recovery / 100))
        return targetFloor + (targetCeiling - targetFloor) * share
    }

    // MARK: - Scoring

    public static func of(_ input: StrainInput) -> SignalScore {
        let samples = input.samples.filter(\.isUsable)
        let muscular = muscularLoad(hardSets: input.hardSets)

        guard !samples.isEmpty || muscular > 0 else {
            return fallbackScore(input.fallback)
        }

        let resting = input.restingHeartRate ?? assumedRestingHeartRate
        let maximum = maximumHeartRate(ageYears: input.ageYears,
                                       observed: input.observedMaxHeartRate)

        // Time and load per zone, so the breakdown can say where the day was spent
        // rather than only how much it cost.
        var minutesByZone: [String: Double] = [:]
        var loadByZone: [String: Double] = [:]
        var everydayRaw = 0.0
        var everydayMinutes = 0.0
        for sample in samples {
            let reserve = min(max((sample.beatsPerMinute - resting) / max(maximum - resting, 1), 0), 1)
            let id = zone(forReserve: reserve).id
            let load = trimp(minutes: sample.minutes, heartRate: sample.beatsPerMinute,
                             resting: resting, maximum: maximum, sex: input.biologicalSex)
            // Split across the ramp rather than assigned to one side of a line, and the
            // minutes split with the load, or the two disagree about the same sample. They
            // did: a trace whose every reading sat inside the ramp put everyday load in
            // zone0 and no minutes there, and the row is emitted only where there are
            // minutes, so that load vanished from the breakdown while staying in the ring.
            // Measured on 45 minutes at 108 bpm: ring 21.19, rows summing to 10.21.
            let training = trainingShare(reserve: reserve)
            minutesByZone[id, default: 0] += sample.minutes * training
            everydayMinutes += sample.minutes * (1 - training)
            loadByZone[id, default: 0] += load * training
            everydayRaw += load * (1 - training)
        }

        // Being awake saturates rather than clamping, so the bottom of the scale keeps
        // its resolution: a hard ceiling made every easy day read exactly the same
        // number by mid-morning and then stop moving for the rest of it.
        let everyday = everydayLoadCap * (1 - exp(-everydayRaw / everydayLoadCap))
        loadByZone[zones[zones.count - 1].id, default: 0] += everyday
        minutesByZone[zones[zones.count - 1].id, default: 0] += everydayMinutes

        let total = loadByZone.values.reduce(0, +) + muscular
        let value = strain(load: total)

        // Strain's neutral point is zero, so the rows sum to the number itself. A day
        // with no load at all gives every row a magnitude of zero rather than a
        // division by it.
        let share = total > 0 ? value / total : 0
        let heaviest = Swift.max(loadByZone.values.max() ?? 0, muscular)

        var rows: [ScoreContributor] = zones.compactMap { zone in
            guard let minutes = minutesByZone[zone.id], minutes > 0 else { return nil }
            let load = loadByZone[zone.id] ?? 0
            return ScoreContributor(
                id: zone.id,
                title: zone.title,
                value: minutes,
                unit: "min",
                comparison: nil,
                comparisonLabel: nil,
                state: .fine,
                level: heaviest > 0 ? load / heaviest : 0,
                symbol: zone.symbol,
                magnitude: load * share,
                explanation: explanation(for: zone))
        }

        if muscular > 0 {
            rows.append(ScoreContributor(
                id: muscularContributorID,
                title: "Lifting",
                value: Double(input.hardSets),
                unit: input.hardSets == 1 ? "hard set" : "hard sets",
                comparison: nil,
                comparisonLabel: nil,
                state: .fine,
                level: heaviest > 0 ? muscular / heaviest : 0,
                symbol: "dumbbell.fill",
                magnitude: muscular * share,
                explanation: "Sets taken within about three reps of failure. A heavy "
                           + "triple barely moves your heart rate, so lifting is close "
                           + "to invisible to a cardiac measure. It is counted "
                           + "separately rather than missed."))
        }

        var missing: [String] = []
        if samples.isEmpty { missing.append("Heart rate") }
        // Where the hole is, not how much of the day carried samples.
        //
        // The two tests this replaces were both shares of the span, and a share cannot
        // localise a hole. The ordinary way a load measure gets lied to is the watch
        // coming off to train: ninety minutes missing out of sixteen hours is a sampled
        // share of 0.91, so catching it through density would have wanted a threshold of
        // 0.91, at which point every normal day is thin too. Measured, a hole over the
        // session had to pass eight and a half hours before either test fired: 22.9
        // against a true 65.5, reported as a complete day.
        //
        // A contiguous stretch of unobserved time is the thing that can hide a session,
        // so that is what gets measured, across the waking window and including both
        // edges. It subsumes what the old pair caught: two readings twelve hours apart
        // are a twelve-hour gap, and a watch put on in the evening is a leading one.
        if !samples.isEmpty, let first = samples.map(\.start).min() {
            // The window runs from waking, when the night says when that was. When it
            // does not, it runs from the first reading, which finds internal and
            // trailing holes but is blind to a late start, so that one case is answered
            // by the floor below instead of by a guessed hour.
            let gap = largestUnobservedGap(in: samples,
                                           from: WakingDay.start(of: input.asleepPeriods,
                                                                 primary: input.primarySleep,
                                                                 on: input.readAt) ?? first,
                                           to: input.readAt,
                                           asleep: input.asleepPeriods)
            if gap >= unobservedGapMinutes || fallsShortOfTheDay(input, from: first) {
                missing.append("Part of the day, your heart rate was recorded for about "
                               + recorded(samples.reduce(0) { $0 + $1.minutes }))
            }
        }
        if input.ageYears == nil { missing.append("Your age, so your maximum heart rate is assumed") }
        if input.restingHeartRate == nil { missing.append("Resting heart rate") }
        if input.biologicalSex == nil { missing.append("Biological sex") }

        return SignalScore(
            kind: .strain,
            value: value,
            band: .strain(value: value),
            contributors: rows.sorted { abs($0.magnitude) > abs($1.magnitude) },
            coverage: missing.isEmpty ? .full : .partial,
            missing: missing,
            modelVersion: modelVersion)
    }

    /// How much was recorded, in the unit that can express it. Rounding a short trace to
    /// hours produced "your heart rate was recorded for about 0 hours", which is a sentence
    /// about nothing, beside a ring showing a real number.
    private static func recorded(_ minutes: Double) -> String {
        guard minutes >= 60 else {
            let count = Swift.max(1, Int(minutes.rounded()))
            return "\(count) \(count == 1 ? "minute" : "minutes")"
        }
        let hours = Int((minutes / 60).rounded())
        return "\(hours) \(hours == 1 ? "hour" : "hours")"
    }

    /// Whether the trace is too short to be describing the waking day that has provably
    /// happened by now. Only consulted when the night is unknown; with a wake time the
    /// leading gap already says this, and says it more precisely.
    private static func fallsShortOfTheDay(_ input: StrainInput, from first: Date) -> Bool {
        guard WakingDay.start(of: input.asleepPeriods, primary: input.primarySleep,
                              on: input.readAt) == nil else { return false }
        let sinceMidnight = input.readAt
            .timeIntervalSince(Calendar.current.startOfDay(for: input.readAt)) / 60
        let wakingSoFar = sinceMidnight - maximumSleepMinutes
        guard wakingSoFar > 0 else { return false }
        // From the same list `first` came from. Reading `input.samples` here instead meant
        // a single trailing sample with a non-finite length would make `span` NaN and
        // switch the floor off without a word. Nothing produces one today.
        let usable = input.samples.filter { $0.minutes.isFinite && $0.beatsPerMinute.isFinite }
        let last = usable.max(by: { $0.start < $1.start })
        let span = (last?.start.timeIntervalSince(first) ?? 0) / 60 + (last?.minutes ?? 0)
        return span < wakingSoFar
    }

    /// The longest contiguous run of minutes inside the window that no sample describes,
    /// counting the stretch before the first reading and the stretch after the last.
    ///
    /// Samples before the window start are not a gap: somebody read at nine in the
    /// morning wore the watch through a night this window does not reach back to.
    private static func largestUnobservedGap(in samples: [HeartRateSample],
                                            from start: Date, to end: Date,
                                            asleep: [DateInterval]) -> Double {
        let ordered = samples.sorted { $0.start < $1.start }
        var largest = 0.0
        for window in awakeWindows(from: start, to: end, asleep: asleep) {
            var cursor = window.start
            for sample in ordered {
                let finish = sample.start.addingTimeInterval(sample.minutes * 60)
                guard finish > cursor, sample.start < window.end else { continue }
                largest = Swift.max(largest, sample.start.timeIntervalSince(cursor) / 60)
                cursor = finish
            }
            largest = Swift.max(largest, window.end.timeIntervalSince(cursor) / 60)
        }
        return largest
    }

    /// The window, minus every stretch of it spent asleep. Sleep is not a hole in the
    /// record (it is the one part of the day nobody expects a heart rate from) and
    /// counting it as one flagged watches that never came off.
    private static func awakeWindows(from start: Date, to end: Date,
                                     asleep: [DateInterval]) -> [DateInterval] {
        guard end > start else { return [] }
        var windows: [DateInterval] = []
        var cursor = start
        for period in asleep.sorted(by: { $0.start < $1.start }) {
            if period.end <= cursor { continue }
            if period.start >= end { break }
            if period.start > cursor {
                windows.append(DateInterval(start: cursor, end: Swift.min(period.start, end)))
            }
            cursor = Swift.max(cursor, period.end)
        }
        if cursor < end { windows.append(DateInterval(start: cursor, end: end)) }
        return windows
    }

    /// No cardiac trace at all: the ordinary case for anybody without a watch. The ring
    /// falls back to the activity comparison that shipped before this engine, and says
    /// so, because an empty ring is worse than a labelled approximation.
    private static func fallbackScore(_ fallback: DailyStrainResult?) -> SignalScore {
        guard let fallback else {
            return SignalScore(kind: .strain, value: nil, band: nil, contributors: [],
                               coverage: .unavailable,
                               missing: ["Heart rate", "Recorded activity"],
                               modelVersion: modelVersion)
        }
        guard let percent = fallback.percent else {
            return SignalScore(kind: .strain, value: nil, band: nil, contributors: [],
                               coverage: .buildingBaseline,
                               missing: ["Heart rate"],
                               modelVersion: modelVersion)
        }
        let value = scaleMax * Double(percent) / 100
        return SignalScore(
            kind: .strain,
            value: value,
            // No band. A percentile of your own days is not a position on an absolute
            // scale, and calling somebody's laziest-but-one day "all out" because it
            // beat the other thirteen would be a lie told in colour.
            band: nil,
            contributors: [ScoreContributor(
                id: "activity",
                title: fallback.metric.label,
                value: fallback.value,
                unit: fallback.metric.unit,
                comparison: nil,
                comparisonLabel: nil,
                state: .fine,
                level: Double(percent) / 100,
                symbol: "flame.fill",
                magnitude: value,
                explanation: "Without heart rate there is no way to measure how hard "
                           + "today actually was, so this compares today's \(fallback.metric.label.lowercased()) "
                           + "against your own last \(fallback.baselineDays) recorded days. "
                           + "It says where today sits among your days, not what it cost you.")],
            coverage: .partial,
            missing: ["Heart rate"],
            modelVersion: modelVersion)
    }

    private static func explanation(for zone: Zone) -> String {
        switch zone.id {
        case "zone0":
            return "Below the first training zone. Walking about, standing, everything "
                 + "that is not a session. It is not nothing: a long day on your feet "
                 + "accumulates here, but each minute is worth very little."
        case "zone1", "zone2":
            return "Easy aerobic work, the pace you could hold a conversation at. Most "
                 + "endurance training should live here, and it costs little to recover from."
        case "zone3":
            return "Steady work where talking gets awkward. Real training stimulus, and "
                 + "the first zone where minutes start to add up quickly."
        case "zone4":
            return "Hard work near your threshold. Each minute is worth several down in "
                 + "the easy zones, which is why the scale is not linear."
        default:
            return "Close to your maximum. The most expensive minutes you can spend, and "
                 + "the ones that will still be showing in tomorrow's recovery."
        }
    }
}
