import Foundation

/// The physiological inputs the readiness model reads.
/// Wrist temperature is deliberately absent from the weighted set: per spec 3.3 it
/// enters as a binary illness gate, not a graded contributor.
public enum MetricKind: String, CaseIterable, Sendable, Codable {
    case hrv
    case restingHeartRate
    case sleepDebt
    case respiratoryRate
    case bloodOxygen

    /// +1 when a higher value means a better-recovered athlete, -1 when it means worse.
    public var polarity: Double {
        switch self {
        case .hrv, .bloodOxygen: return 1
        case .restingHeartRate, .sleepDebt, .respiratoryRate: return -1
        }
    }

    /// Whether the engine should score this metric's seven-day average rather than
    /// today's reading.
    ///
    /// Only HRV. It is the noisiest input the app has, its night-to-night swing is
    /// mostly measurement and sleep position rather than recovery, and the
    /// athlete-monitoring literature is fairly consistent that the rolling average
    /// carries the signal. The steady metrics are left alone: smoothing a resting heart
    /// rate would throw away exactly the one-day step that makes it worth having.
    public var scoresOnTrend: Bool { self == .hrv }

    public var displayName: String {
        switch self {
        case .hrv: return "Heart rate variability"
        case .restingHeartRate: return "Resting heart rate"
        case .sleepDebt: return "Sleep debt"
        case .respiratoryRate: return "Respiratory rate"
        case .bloodOxygen: return "Blood oxygen"
        }
    }

    /// What this actually is, for somebody who has never heard of it.
    ///
    /// Plain language, no clinical framing, and it always says which direction means
    /// what. A number nobody understands is decoration, and half of these are acronyms
    /// a watch started showing people without ever explaining them.
    public var explanation: String {
        switch self {
        case .hrv:
            return "The variation in time between heartbeats, measured while you sleep. "
                 + "Higher usually means your nervous system has recovered. It drops "
                 + "when you are under training load, short on sleep, stressed, or "
                 + "coming down with something. Normal values differ hugely between "
                 + "people, which is why this is scored against your own history and "
                 + "never against anyone else's."
        case .restingHeartRate:
            return "Your heart rate at complete rest, taken overnight. It is one of the "
                 + "steadiest numbers your body produces, so a rise of a few beats is "
                 + "worth noticing. It tends to go up when you are still recovering "
                 + "from hard training, under-slept, drinking, or fighting something off."
        case .sleepDebt:
            return "How far behind you are over your last seven nights of sleep, "
                 + "measured against the "
                 + "middle of your own recent nights, with a floor at seven hours so a "
                 + "long habit of short sleep cannot quietly become the target. It accumulates "
                 + "and it is paid back the same way: three nights an hour short is the "
                 + "same hole as one very bad night, and a long night takes some of it "
                 + "off. Zero is the target, and unlike everything else here that target "
                 + "is the same for everybody."
        case .respiratoryRate:
            return "Breaths per minute while you sleep. It barely moves night to night, "
                 + "so even a small rise stands out. It usually goes up before you feel "
                 + "anything, which is what makes it useful."
        case .bloodOxygen:
            return "The share of your red blood cells carrying oxygen, measured "
                 + "overnight. It normally sits in a narrow band in the high nineties, "
                 + "so a drop that looks small on paper is a bigger move than it "
                 + "appears. Higher is better."
        }
    }

    /// The glyph that stands in for this metric's name on a tile too small for words.
    public var symbol: String {
        switch self {
        case .hrv: return "waveform.path.ecg"
        case .restingHeartRate: return "heart.fill"
        case .sleepDebt: return "bed.double.fill"
        case .respiratoryRate: return "lungs.fill"
        case .bloodOxygen: return "drop.fill"
        }
    }

    public var unit: String {
        switch self {
        case .hrv: return "ms"
        case .restingHeartRate: return "bpm"
        case .sleepDebt: return "h"
        case .respiratoryRate: return "br/min"
        case .bloodOxygen: return "%"
        }
    }
}

/// One metric on one day: what it read, what this user's own baseline is, and the
/// standardised distance between them.
public struct MetricReading: Sendable, Equatable, Codable {
    public let kind: MetricKind
    public let value: Double
    public let baseline: Double
    /// Today against the baseline. This is the one shown, so the words under a number
    /// always describe the number beside them.
    public let zScore: Double
    /// What the engine actually weighs. The same as `zScore` for every metric except
    /// HRV, which is scored on its trend — see `MetricKind.scoresOnTrend`.
    public let scoringZ: Double
    public let sampleCount: Int

    /// Whether the measurement itself sits above its baseline.
    ///
    /// Not the same question as whether that is good news, and the two diverge for
    /// every inverted metric. Call sites that derived this from the aligned z told the
    /// user a resting heart rate of 70 against a baseline of 53 was "below usual".
    public var isAboveBaseline: Bool { zScore > 0 }

    /// Whether the reading is good news, which is the aligned question.
    public var isFavourable: Bool { zScore * kind.polarity >= 0 }

    public init(kind: MetricKind, value: Double, baseline: Double, zScore: Double,
                scoringZ: Double? = nil, sampleCount: Int) {
        self.kind = kind
        self.value = value
        self.baseline = baseline
        self.zScore = zScore
        self.scoringZ = scoringZ ?? zScore
        self.sampleCount = sampleCount
    }
}
