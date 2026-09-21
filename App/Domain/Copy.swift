import Foundation

/// Every user-facing string that describes a decision. Kept together so the product's
/// voice is one thing rather than scattered through views.
enum Copy {

    /// "1 hard set" / "2 hard sets". Cheap, and it stops the same bug recurring.
    static func count(_ n: Int, _ singular: String, plural: String? = nil) -> String {
        "\(n) " + (n == 1 ? singular : (plural ?? singular + "s"))
    }


    /// Where a reading sits in the user's own range. Not a grade (the app has no
    /// basis for calling a number "excellent") and not a verdict either: this is the
    /// measurement's own direction, so it takes the raw z, never the aligned one.
    static func position(_ z: Double) -> String {
        switch z {
        case 1...:      return "Above usual"
        case ..<(-1):   return "Below usual"
        default:        return "Usual"
        }
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
    ///
    /// `hasSession` is not decoration: telling somebody with no programme to "run the
    /// session as planned" names a thing that does not exist, and the goals that skip
    /// training entirely are exactly the ones most likely to hit this.
    static func call(for recommendation: Recommendation, gate: ReadinessGate?,
                     hasSession: Bool = true) -> String {
        if gate == .elevatedWristTemperature {
            return hasSession
                ? "Temperature is up. Skip it or keep it easy."
                : "Temperature is up. Take it easy today."
        }
        // No "baseline". It is a word this app invented for its own arithmetic, and it
        // was standing in front of every instruction, making the reader translate before
        // they could act. Wherever this appears the numbers are on the same screen, and
        // Jett's morning line names them in words before it gets here.
        switch recommendation.state {
        case .push:
            return hasSession ? "Train as planned." : "Good day to move."
        case .maintain:
            return hasSession ? "Run the session as planned." : "Nothing's off today."
        case .reduce:
            return hasSession ? "Cut volume, keep reps in reserve." : "Keep it gentle today."
        case .recover:
            return hasSession ? "Move, don't train hard." : "Rest today."
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
        "\(contribution.kind.displayName) \(deviation(contribution.zScore))"
    }

    /// How far a reading sits from its own baseline, in the measurement's own
    /// direction. Raw z, never the contribution's sign: a raised resting heart rate
    /// contributes negatively but the reading itself is *above* baseline.
    static func deviation(_ z: Double) -> String {
        let direction = z < 0 ? "below" : "above"
        let strength: String
        switch abs(z) {
        case 2...: strength = "well "
        case 1..<2: strength = ""
        default: strength = "slightly "
        }
        return "\(strength)\(direction) baseline"
    }

    /// Iconography lives with the words because they are one voice: an adjustment and
    /// the glyph that stands for it should never be chosen independently.
    static func symbol(for adjustment: SessionAdjustment) -> String {
        switch adjustment {
        case .proceedAsPlanned:         return "checkmark"
        case .reduceWorkingSets:        return "rectangle.stack"
        case .capEffort:                return "gauge.medium"
        case .reduceLoad:               return "scalemass"
        case .deferLowerBody:           return "calendar.badge.clock"
        case .swapConditioningToZone2:  return "figure.run"
        }
    }

    static func symbol(for kind: MetricKind) -> String {
        switch kind {
        case .hrv:              return "waveform.path.ecg"
        case .restingHeartRate: return "heart.fill"
        case .sleepDebt:        return "moon.zzz.fill"
        case .respiratoryRate:  return "lungs.fill"
        case .bloodOxygen:      return "drop.fill"
        }
    }

    static func confidenceNote(_ confidence: ReadinessConfidence, days: Int) -> String? {
        guard confidence == .low else { return nil }
        return "Calibrating · \(count(days, "day"))"
    }
}
