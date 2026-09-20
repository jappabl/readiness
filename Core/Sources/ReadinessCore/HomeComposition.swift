import Foundation

/// Why someone opened the app. Not a label on a profile screen — it decides what the
/// home screen is made of.
public enum TrainingGoal: String, Sendable, Codable, CaseIterable, Equatable {
    case getStronger
    case buildMuscle
    case loseFat
    case feelBetter

    public var title: String {
        switch self {
        case .getStronger: return "Get stronger"
        case .buildMuscle: return "Build muscle"
        case .loseFat:     return "Lose fat"
        case .feelBetter:  return "Feel better"
        }
    }

    /// What the app will actually do about it. Concrete, because a goal picker whose
    /// options are one word each is a personality quiz.
    public var promise: String {
        switch self {
        case .getStronger: return "Loads prescribed against how recovered you are"
        case .buildMuscle: return "Volume and protein tracked against your weight"
        case .loseFat:     return "Energy in against energy out, without losing strength"
        case .feelBetter:  return "Sleep, movement and recovery, without a training plan"
        }
    }

    public var symbol: String {
        switch self {
        case .getStronger: return "figure.strengthtraining.traditional"
        case .buildMuscle: return "figure.arms.open"
        case .loseFat:     return "flame"
        case .feelBetter:  return "leaf"
        }
    }

    /// Whether the goal implies a barbell programme. Used to decide whether to ask.
    public var impliesLifting: Bool {
        switch self {
        case .getStronger, .buildMuscle: return true
        case .loseFat, .feelBetter:      return false
        }
    }
}

/// One section of the home screen.
public enum HomeBlock: String, Sendable, Equatable, CaseIterable {
    case session
    case programPrompt
    case nutrition
    case weightTrend
    case sleepQuality
    case movement
    case healthMonitor
}

public enum HomeComposition {

    /// Combine every selected goal in stable display order, with shared cards once.
    public static func blocks(for goals: Set<TrainingGoal>, hasProgram: Bool) -> [HomeBlock] {
        var result: [HomeBlock] = []
        for goal in TrainingGoal.allCases where goals.contains(goal) {
            for block in blocks(for: goal, hasProgram: hasProgram)
                where block != .healthMonitor && !result.contains(block) {
                result.append(block)
            }
        }
        return result + [.healthMonitor]
    }


    /// What today's screen is made of, in order.
    ///
    /// The rule worth stating plainly: the barbell angle cannot be the front page for
    /// everybody. Someone here to sleep better opens on their sleep, and only reaches
    /// their programme further down — if they have one at all.
    public static func blocks(for goal: TrainingGoal, hasProgram: Bool) -> [HomeBlock] {
        // Someone whose goal is lifting, with nothing to lift, gets asked — not an
        // empty screen, and not a session that does not exist.
        let lead: HomeBlock = hasProgram ? .session : .programPrompt
        let body: [HomeBlock]
        switch goal {
        case .getStronger:
            body = [lead]
        case .buildMuscle:
            body = [lead, .nutrition, .weightTrend]
        case .loseFat:
            // Keep calories and macros together, without inferring a deficit from an incomplete log.
            // The session stays, below it, so training does not quietly disappear.
            body = [.nutrition, .weightTrend, .session]
        case .feelBetter:
            body = [.sleepQuality, .movement, .session]
        }

        // A promised session with no programme behind it is a broken promise.
        return body.filter { $0 != .session || hasProgram } + [.healthMonitor]
    }
}
