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

    public var displayName: String {
        switch self {
        case .hrv: return "Heart rate variability"
        case .restingHeartRate: return "Resting heart rate"
        case .sleepDebt: return "Sleep debt"
        case .respiratoryRate: return "Respiratory rate"
        case .bloodOxygen: return "Blood oxygen"
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
    public let zScore: Double
    public let sampleCount: Int

    public init(kind: MetricKind, value: Double, baseline: Double, zScore: Double, sampleCount: Int) {
        self.kind = kind
        self.value = value
        self.baseline = baseline
        self.zScore = zScore
        self.sampleCount = sampleCount
    }
}
