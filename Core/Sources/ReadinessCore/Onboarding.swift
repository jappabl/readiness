import Foundation

/// How often someone actually trains. Asked because it changes what the app should
/// expect of them, not to compute a score.
public enum TrainingFrequency: String, Sendable, Codable, CaseIterable, Equatable {
    case rarely
    case few
    case most
    case daily

    public var title: String {
        switch self {
        case .rarely: return "0–2"
        case .few:    return "3–4"
        case .most:   return "5–6"
        case .daily:  return "Every day"
        }
    }

    public var detail: String {
        switch self {
        case .rarely: return "Now and then"
        case .few:    return "A few times a week"
        case .most:   return "Most days"
        case .daily:  return "Training is the routine"
        }
    }

    public var symbol: String {
        switch self {
        case .rarely: return "circle"
        case .few:    return "circle.lefthalf.filled"
        case .most:   return "circle.righthalf.filled"
        case .daily:  return "circle.fill"
        }
    }

    /// Sessions per week, used to sanity-check acute load rather than to grade anyone.
    public var sessionsPerWeek: ClosedRange<Int> {
        switch self {
        case .rarely: return 0...2
        case .few:    return 3...4
        case .most:   return 5...6
        case .daily:  return 7...7
        }
    }
}

/// What the user says gets in the way. Given to the coach as context, never scored.
public enum Obstacle: String, Sendable, Codable, CaseIterable, Equatable {
    case consistency
    case sleep
    case stress
    case nutrition
    case soreness
    case time

    public var title: String {
        switch self {
        case .consistency: return "Staying consistent"
        case .sleep:       return "Not sleeping enough"
        case .stress:      return "Stress"
        case .nutrition:   return "Eating well"
        case .soreness:    return "Soreness and niggles"
        case .time:        return "Not enough time"
        }
    }

    public var symbol: String {
        switch self {
        case .consistency: return "repeat"
        case .sleep:       return "moon.zzz"
        case .stress:      return "wind"
        case .nutrition:   return "fork.knife"
        case .soreness:    return "bandage"
        case .time:        return "clock"
        }
    }
}

/// Everything onboarding collects. Deliberately small: each field has to change what
/// the app does, or it is a question asked for the sake of feeling thorough.
public struct OnboardingAnswers: Sendable, Codable, Equatable {
    public var goal: TrainingGoal?
    public var frequency: TrainingFrequency?
    public var obstacles: Set<Obstacle> = []
    public var unitsAreMetric = false

    public init() {}

    /// Which steps still need an answer before the flow can finish.
    public var isComplete: Bool { goal != nil && frequency != nil }
}
