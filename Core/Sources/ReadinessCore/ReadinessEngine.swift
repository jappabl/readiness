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
    public static let modelVersion = "v0.1.0"

    /// Phase 1 weights, from published effect sizes. Stated openly, summing to 1.0 so the
    /// composite is a plain weighted mean of z-scores and the arithmetic checks by hand.
    /// Wrist temperature and ACWR are deliberately absent: they are gates, not contributors.
    public static let weights: [MetricKind: Double] = [
        .hrv: 0.40,
        .restingHeartRate: 0.25,
        .sleepDebt: 0.20,
        .respiratoryRate: 0.10,
        .bloodOxygen: 0.05,
    ]

    public static let wristTemperatureGateC: Double = 0.5
    public static let acwrGate: Double = 1.5
    public static let minimumConfidentDays: Int = 14

    /// No single morning is decisive: an extreme reading is clamped before it is weighted.
    public static let zClamp: Double = 3.0

    public static func evaluate(_ input: ReadinessInput) -> ReadinessResult {
        let confidence: ReadinessConfidence =
            input.daysOfHistory >= minimumConfidentDays ? .normal : .low

        let present = input.readings.filter { weights[$0.kind] != nil }
        let totalWeight = present.reduce(0.0) { $0 + (weights[$1.kind] ?? 0) }

        guard totalWeight > 0 else {
            return ReadinessResult(state: .atBaseline, composite: 0, contributions: [],
                                   confidence: .low, gateApplied: nil,
                                   modelVersion: modelVersion)
        }

        // Renormalise over the inputs actually present, so a missing stream dilutes
        // nothing — it simply stops voting.
        let contributions = present.map { reading -> InputContribution in
            let weight = (weights[reading.kind] ?? 0) / totalWeight
            let clamped = Swift.min(Swift.max(reading.zScore, -zClamp), zClamp)
            let aligned = clamped * reading.kind.polarity
            return InputContribution(kind: reading.kind, zScore: reading.zScore,
                                     weight: weight, points: weight * aligned)
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

    /// Four states, thresholded on standard deviations from the user's own baseline.
    /// Four is what the data supports; a 0-100 score would claim about 100.
    static func state(for composite: Double) -> ReadinessState {
        switch composite {
        case 0.5...: return .aboveBaseline
        case -0.5..<0.5: return .atBaseline
        case -1.5..<(-0.5): return .belowBaseline
        default: return .wellBelowBaseline
        }
    }
}
