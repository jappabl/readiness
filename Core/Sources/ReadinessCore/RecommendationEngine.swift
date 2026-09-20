import Foundation

public struct RecommendationInput: Sendable {
    public let readiness: ReadinessResult
    public let checkIn: CheckIn?
    public let acwr: Double?
    public let hasPlannedLowerBody: Bool
    public let hasPlannedConditioning: Bool

    public init(readiness: ReadinessResult, checkIn: CheckIn? = nil, acwr: Double? = nil,
                hasPlannedLowerBody: Bool = false, hasPlannedConditioning: Bool = false) {
        self.readiness = readiness
        self.checkIn = checkIn
        self.acwr = acwr
        self.hasPlannedLowerBody = hasPlannedLowerBody
        self.hasPlannedConditioning = hasPlannedConditioning
    }
}

/// The constrained decision layer. Deterministic and inspectable: the language model
/// explains what this produces, and never produces it itself.
public enum RecommendationEngine {
    /// The most a subjective morning can move the physiological composite, in SD.
    public static let maximumCheckInShift = 0.5

    public static func recommend(_ input: RecommendationInput) -> Recommendation {
        let shift = input.checkIn.map(checkInShift) ?? 0
        var state = trainingState(for: input.readiness.composite + shift)

        // An acute load spike cancels a green light. It never manufactures a bad day,
        // and it never rescues one.
        if let acwr = input.acwr, acwr > ReadinessEngine.acwrGate, state == .push {
            state = .maintain
        }

        // Illness outranks everything, including a strong morning.
        if input.readiness.gateApplied == .elevatedWristTemperature {
            state = .recover
        }

        return Recommendation(
            state: state,
            adjustments: adjustments(for: state, input: input),
            evidence: Array(input.readiness.contributions.sorted { $0.points < $1.points }.prefix(3)),
            uncertainty: uncertainty(for: input),
            confidence: input.readiness.confidence,
            modelVersion: input.readiness.modelVersion)
    }

    /// How far the morning check-in moves the physiological composite, in SD.
    /// Deliberately bounded: what someone reports is information, not an override.
    public static func checkInShift(_ checkIn: CheckIn) -> Double {
        let fields = [checkIn.soreness, checkIn.energy, checkIn.stress, checkIn.mood]
        let mean = Double(fields.reduce(0, +)) / Double(fields.count)
        // Fields run 1...5 around a neutral 3, so (mean - 3) / 2 lands in -1...1.
        let normalised = (mean - 3) / 2
        return max(-maximumCheckInShift, min(maximumCheckInShift, normalised * maximumCheckInShift))
    }

    /// Read off the recovery scale, for the same reason `ReadinessEngine.state(for:)` is:
    /// a session called "maintain" underneath a red ring is the app disagreeing with
    /// itself in front of the user. The boundaries are the recovery bands.
    static func trainingState(for composite: Double) -> TrainingState {
        switch RecoveryScore.percent(composite: composite) {
        case 67...: return .push
        case 34..<67: return .maintain
        case 15..<34: return .reduce
        default: return .recover
        }
    }

    /// The smallest concrete change that fits the evidence.
    static func adjustments(for state: TrainingState,
                            input: RecommendationInput) -> [SessionAdjustment] {
        switch state {
        case .push, .maintain:
            return [.proceedAsPlanned]

        case .reduce:
            // Trim volume and effort before touching the bar: the load is what drives
            // adaptation, and the extra sets are what cost recovery.
            return [.reduceWorkingSets(percent: 20), .capEffort(rir: 3)]

        case .recover:
            var actions: [SessionAdjustment] = [.reduceLoad(percent: 15), .capEffort(rir: 4)]
            if input.hasPlannedLowerBody { actions.append(.deferLowerBody) }
            if input.hasPlannedConditioning { actions.append(.swapConditioningToZone2) }
            return actions
        }
    }

    static func uncertainty(for input: RecommendationInput) -> [String] {
        var notes: [String] = []
        if input.readiness.confidence == .low {
            notes.append("Baseline under \(ReadinessEngine.minimumConfidentDays) days.")
        }
        if input.checkIn == nil {
            notes.append("No check-in today.")
        }
        if input.acwr == nil {
            notes.append("Not enough training history.")
        }
        return notes
    }
}
