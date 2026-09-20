import Foundation

public enum ReadinessState: String, Sendable, Codable, CaseIterable {
    case aboveBaseline
    case atBaseline
    case belowBaseline
    case wellBelowBaseline
}

public enum ReadinessConfidence: String, Sendable, Codable {
    case low
    case normal
}

public struct InputContribution: Sendable, Equatable, Codable {
    public let kind: MetricKind
    public let zScore: Double
    public let weight: Double
    public let points: Double
    /// The aligned z the engine actually weighed, before clamping. Optional because
    /// these are persisted as evidence and older rows predate it.
    public var alignedZ: Double?

    public init(kind: MetricKind, zScore: Double, weight: Double, points: Double,
                alignedZ: Double? = nil) {
        self.kind = kind
        self.zScore = zScore
        self.weight = weight
        self.points = points
        self.alignedZ = alignedZ
    }
}

public struct ReadinessResult: Sendable, Equatable, Codable {
    public let state: ReadinessState
    public let composite: Double
    public let contributions: [InputContribution]
    public let confidence: ReadinessConfidence
    public let gateApplied: ReadinessGate?
    public let modelVersion: String
}

public enum ReadinessGate: String, Sendable, Codable, Equatable {
    case elevatedWristTemperature
    case acuteLoadSpike

    public var displayName: String {
        switch self {
        case .elevatedWristTemperature: return "Raised overnight temperature"
        case .acuteLoadSpike: return "Training load spike"
        }
    }

    public var explanation: String {
        switch self {
        case .elevatedWristTemperature:
            return "Your sleeping wrist temperature was well above your own normal. "
                 + "That is the earliest sign the body gives that it is fighting "
                 + "something, and it outranks every other reading here. A strong HRV "
                 + "on a morning like this is not the news it looks like."
        case .acuteLoadSpike:
            return "The last week of training is well above what the last month has "
                 + "prepared you for. This cannot make a good morning bad, but it will "
                 + "stop one being called a green light."
        }
    }
}

public struct ReadinessInput: Sendable {
    public let readings: [MetricReading]
    public let wristTemperatureDeviationC: Double?
    public let acwr: Double?
    public let daysOfHistory: Int

    public init(readings: [MetricReading], wristTemperatureDeviationC: Double? = nil,
                acwr: Double? = nil, daysOfHistory: Int) {
        self.readings = readings
        self.wristTemperatureDeviationC = wristTemperatureDeviationC
        self.acwr = acwr
        self.daysOfHistory = daysOfHistory
    }
}

public enum ReadinessEngine {
    public static let modelVersion = "v0.2.0"

    /// Stated openly, summing to 1.0 so the composite is a plain weighted mean and the
    /// arithmetic checks by hand. Wrist temperature and ACWR are deliberately absent:
    /// they are gates, not contributors.
    ///
    /// These are still assumptions rather than anything measured on this app's users,
    /// but they are ordered by how much each input can be trusted. Sleep leads: it is
    /// the most causally established driver of how tomorrow goes, and the only one
    /// somebody can act on directly. Resting heart rate is next, being steady enough
    /// that a few beats mean something. HRV keeps a real share but no longer decides
    /// the day alone: it is the noisiest thing here, and it previously held the
    /// largest weight purely because convention says it should.
    ///
    /// The honest end state is weights learned per person from their own outcomes. This
    /// is a better guess in the meantime.
    public static let weights: [MetricKind: Double] = [
        .sleepDebt: 0.30,
        .restingHeartRate: 0.25,
        .hrv: 0.25,
        .respiratoryRate: 0.13,
        .bloodOxygen: 0.07,
    ]

    public static let wristTemperatureGateC: Double = 0.5
    public static let acwrGate: Double = 1.5
    public static let minimumConfidentDays: Int = 14

    /// No single morning is decisive: an extreme reading is clamped before it is weighted.
    public static let zClamp: Double = 3.0

    public static func evaluate(_ input: ReadinessInput) -> ReadinessResult {
        // From the readings' own sample counts, not the length of the series.
        //
        // The series counts any day with something in it, and a night of iPhone sleep is
        // enough, so somebody with six months of phone data and a watch bought this week
        // reported full confidence while every heart metric was judged against two
        // samples. The calibration warning never fired for the commonest first-run
        // profile there is. The thinnest baseline in the set is the one that decides.
        let samples = input.readings.filter { weights[$0.kind] != nil }.map(\.sampleCount)
        let confidence: ReadinessConfidence =
            (samples.min() ?? 0) >= minimumConfidentDays ? .normal : .low

        let present = input.readings.filter { weights[$0.kind] != nil }
        let totalWeight = present.reduce(0.0) { $0 + (weights[$1.kind] ?? 0) }

        guard totalWeight > 0 else {
            return ReadinessResult(state: .atBaseline, composite: 0, contributions: [],
                                   confidence: .low, gateApplied: nil,
                                   modelVersion: modelVersion)
        }

        // Renormalise over the inputs actually present, so a missing stream dilutes
        // nothing: it simply stops voting.
        // Renormalised over the inputs present, but only down to a floor. Above it, a
        // missing stream stops voting and the rest carry the day as before; below it the
        // composite is damped, because two metrics cannot speak for five.
        let confidentWeight = Swift.max(totalWeight, RecoveryScore.minimumConfidentWeight)
        let contributions = present.map { reading -> InputContribution in
            let weight = (weights[reading.kind] ?? 0) / confidentWeight
            // The scoring z, not the displayed one: HRV is weighed on its trend.
            let clamped = Swift.min(Swift.max(reading.scoringZ, -zClamp), zClamp)
            let aligned = clamped * reading.kind.polarity
            // No single input may leave the middle band on its own.
            let points = Swift.min(Swift.max(weight * aligned, -RecoveryScore.contributionClamp),
                                   RecoveryScore.contributionClamp)
            return InputContribution(kind: reading.kind, zScore: reading.zScore,
                                     weight: weight, points: points, alignedZ: aligned)
        }

        let composite = contributions.reduce(0) { $0 + $1.points }
        var state = state(for: composite)
        var gate: ReadinessGate?

        // An acute load spike may cancel an upgrade, but never rescues a poor morning.
        if let acwr = input.acwr, acwr > acwrGate, state == .aboveBaseline {
            state = .atBaseline
            gate = .acuteLoadSpike
        }

        // Temperature is a binary illness flag, not a gradient (spec 3.3). It outranks
        // everything else, including a strong HRV.
        if let deviation = input.wristTemperatureDeviationC, deviation >= wristTemperatureGateC {
            state = .wellBelowBaseline
            gate = .elevatedWristTemperature
        }

        return ReadinessResult(state: state, composite: composite,
                               contributions: contributions, confidence: confidence,
                               gateApplied: gate, modelVersion: modelVersion)
    }

    /// Four states, read off the same scale the ring shows.
    ///
    /// These used to be thresholds on the composite itself, at +/-0.5 and +/-1.5. That
    /// was a second, independent calibration of one quantity, and it was calibrated for
    /// a spread the composite does not have: -1.5 is about a 2.5-sigma day, so
    /// wellBelowBaseline arrived in practice only through the temperature gate. Deriving
    /// both from the score means the ring and the advice under it cannot drift apart.
    static func state(for composite: Double) -> ReadinessState {
        switch RecoveryScore.percent(composite: composite) {
        case 67...: return .aboveBaseline
        case 34..<67: return .atBaseline
        case 10..<34: return .belowBaseline
        default: return .wellBelowBaseline
        }
    }
}
