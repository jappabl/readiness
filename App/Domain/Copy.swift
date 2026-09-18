import Foundation

/// Every user-facing string that describes a decision. Kept together so the product's
/// voice is one thing rather than scattered through views.
enum Copy {

    /// "1 hard set" / "2 hard sets". Cheap, and it stops the same bug recurring.
    static func count(_ n: Int, _ singular: String, plural: String? = nil) -> String {
        "\(n) " + (n == 1 ? singular : (plural ?? singular + "s"))
    }


    static func headline(for state: TrainingState) -> String {
        switch state {
        case .push: return "Push"
        case .maintain: return "Maintain"
        case .reduce: return "Reduce"
        case .recover: return "Recover"
        }
    }

    /// One actionable sentence. "Take it easy" is not an answer.
    static func call(for recommendation: Recommendation, gate: ReadinessGate?) -> String {
        if gate == .elevatedWristTemperature {
            return "Your temperature is up overnight. Skip the session or keep it very easy."
        }
        switch recommendation.state {
        case .push:
            return "You're ahead of your baseline. Train as planned and take the top set if it moves well."
        case .maintain:
            return "Nothing is off. Run the session you already planned."
        case .reduce:
            return "You're under your baseline. Keep the session, cut the volume, and leave reps in reserve."
        case .recover:
            return "Your body is well under baseline. Move, but don't train hard today."
        }
    }

    static func describe(_ adjustment: SessionAdjustment) -> String {
        switch adjustment {
        case .proceedAsPlanned:
            return "Proceed as planned"
        case .reduceWorkingSets(let percent):
            return "Cut working sets by \(percent)%"
        case .capEffort(let rir):
            return "Stop every set at \(rir) reps in reserve"
        case .reduceLoad(let percent):
            return "Take \(percent)% off the bar"
        case .deferLowerBody:
            return "Move lower body to tomorrow"
        case .swapConditioningToZone2:
            return "Swap intervals for easy aerobic work"
        }
    }

    /// Why the call was made, in the user's terms rather than z-scores.
    ///
    /// The direction is the measurement's own, not the contribution's sign. A raised
    /// resting heart rate contributes negatively but the reading itself is *above*
    /// baseline, and saying "below" there is simply false.
    static func describe(_ contribution: InputContribution) -> String {
        let direction = contribution.zScore < 0 ? "below" : "above"
        let magnitude = abs(contribution.zScore)
        let strength: String
        switch magnitude {
        case 2...: strength = "well "
        case 1..<2: strength = ""
        default: strength = "slightly "
        }
        return "\(contribution.kind.displayName) \(strength)\(direction) baseline"
    }

    static func confidenceNote(_ confidence: ReadinessConfidence, days: Int) -> String? {
        guard confidence == .low else { return nil }
        return "Still learning your baseline — \(count(days, "day")) in. Treat this as provisional."
    }
}
