import Foundation

/// One bucket of time at one heart rate. Whatever the source aggregates to — five
/// minute buckets in practice — rather than raw beats.
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
    /// What the ring showed before this engine existed. Used only when there is no
    /// cardiac trace at all, and always labelled.
    public let fallback: DailyStrainResult?

    public init(samples: [HeartRateSample], restingHeartRate: Double?, ageYears: Int?,
                biologicalSex: HealthProfile.BiologicalSex?,
                observedMaxHeartRate: Double? = nil, hardSets: Int = 0,
                fallback: DailyStrainResult? = nil) {
        self.samples = samples
        self.restingHeartRate = restingHeartRate
        self.ageYears = ageYears
        self.biologicalSex = biologicalSex
        self.observedMaxHeartRate = observedMaxHeartRate
        self.hardSets = hardSets
        self.fallback = fallback
    }
}

/// How hard today was, on a 0...21 scale.
///
/// The scale is Whoop's and is derived from Borg's 6...20 rating of perceived exertion,
/// stretched by a point to leave room at the top. What sits underneath it here is
/// Banister's TRIMP, which is published, forty years old and testable — the app does not
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
        // and a single bad beat weeks ago would otherwise widen the reserve forever —
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
    public static let scaleMax = 21.0

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
    /// zone — most of most days, and not nothing: it is where a long day on your feet
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

    /// The most that being awake can contribute, in load.
    ///
    /// The bug this exists for: sixteen waking hours at an unremarkable 70 bpm is 87
    /// load, which on the old curve was a strain of 10 out of 21 — "moderate" — for a
    /// person who did nothing at all. Fifteen hours of sitting outweighed a 45-minute
    /// run, so on a day somebody ran, the breakdown's top row was sitting down.
    ///
    /// Duration cannot be the answer below the first training zone: the cost per minute
    /// is real but tiny, and a day is 1440 of them. Capping it keeps a long day on your
    /// feet worth something without letting it become the day.
    public static let everydayLoadCap = 20.0

    /// Below this many minutes of heart rate, the day is a sample rather than a record.
    /// Half a day, because a watch charged overnight and worn from nine to nine is the
    /// normal case and should not be flagged.
    public static let minimumWornMinutes = 720.0

    static func zone(forReserve reserve: Double) -> Zone {
        zones.first { reserve >= $0.lowerReserve } ?? zones[zones.count - 1]
    }

    public static let muscularContributorID = "muscular"

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
        for sample in samples {
            let reserve = min(max((sample.beatsPerMinute - resting) / max(maximum - resting, 1), 0), 1)
            let id = zone(forReserve: reserve).id
            minutesByZone[id, default: 0] += sample.minutes
            loadByZone[id, default: 0] += trimp(minutes: sample.minutes,
                                                heartRate: sample.beatsPerMinute,
                                                resting: resting, maximum: maximum,
                                                sex: input.biologicalSex)
        }

        // Everything under the first training zone is capped together: see
        // `everydayLoadCap`. Applied after the zones are totalled so the minutes still
        // show truthfully on the tile — it is the cost that is bounded, not the time.
        if let everyday = loadByZone[zones[zones.count - 1].id] {
            loadByZone[zones[zones.count - 1].id] = Swift.min(everyday, everydayLoadCap)
        }

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
                           + "to invisible to a cardiac measure — it is counted "
                           + "separately rather than missed."))
        }

        var missing: [String] = []
        if samples.isEmpty { missing.append("Heart rate") }
        // A watch worn for four hours produces a real number from a fifth of a day, and
        // said nothing about it. Either the session was caught and everything around it
        // was not, or the session was missed and a hard day reads as a rest day.
        let worn = samples.reduce(0) { $0 + $1.minutes }
        if !samples.isEmpty, worn < minimumWornMinutes {
            missing.append("Most of the day — your heart rate was only recorded for "
                           + "\(Int(worn / 60)) hours")
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

    /// No cardiac trace at all — the ordinary case for anybody without a watch. The ring
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
                 + "that is not a session. It is not nothing — a long day on your feet "
                 + "accumulates here — but each minute is worth very little."
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
