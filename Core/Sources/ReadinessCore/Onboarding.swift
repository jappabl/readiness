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

/// Time spent training consistently, rather than how often someone trains now.
public enum TrainingExperience: String, Sendable, Codable, CaseIterable {
    case new, regular, experienced
    public var title: String {
        switch self {
        case .new: return "Just starting"
        case .regular: return "Some experience"
        case .experienced: return "Experienced"
        }
    }
    public var detail: String {
        switch self {
        case .new: return "Under a year"
        case .regular: return "1–3 years"
        case .experienced: return "3+ years"
        }
    }
    public var progression: TrainingProgression {
        switch self {
        case .new: return .linear
        case .regular: return .repsThenLoad
        case .experienced: return .plannedBlocks
        }
    }
}

public enum PhysicalLimitation: String, Sendable, Codable, CaseIterable {
    case lowerBack, knees, shoulders
    public var title: String {
        switch self {
        case .lowerBack: return "Lower back"
        case .knees: return "Knees"
        case .shoulders: return "Shoulders"
        }
    }
    /// Only the structured labels can be safely mapped to this small starter catalog.
    /// Other Profile text is still sent to Jett, but cannot be treated as "no limits".
    public static func from(profileText: String) -> Set<PhysicalLimitation>? {
        let text = profileText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        var result: Set<PhysicalLimitation> = []
        for part in text.split(separator: ",", omittingEmptySubsequences: false) {
            let label = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = allCases.first(where: { $0.title.caseInsensitiveCompare(label) == .orderedSame }) else { return nil }
            result.insert(value)
        }
        return result
    }

}

public enum EquipmentAccess: String, Sendable, Codable, CaseIterable {
    case fullGym, dumbbells, bodyweight
    public var title: String {
        switch self {
        case .fullGym: return "Full gym"
        case .dumbbells: return "Dumbbells only"
        case .bodyweight: return "No equipment"
        }
    }
    public var detail: String {
        switch self {
        case .fullGym: return "Barbells and machines"
        case .dumbbells: return "No bench needed"
        case .bodyweight: return "Bodyweight moves"
        }
    }
}

/// Each answer changes training or coaching. New optional fields also decode from
/// existing saved answers without inventing experience, equipment or cleared limits.
public struct OnboardingAnswers: Sendable, Codable, Equatable {
    /// Legacy single-goal marker for older saved profiles. Consumers use selectedGoals.
    public var goal: TrainingGoal?
    public private(set) var goals: Set<TrainingGoal>?
    public var frequency: TrainingFrequency?
    public var obstacles: Set<Obstacle> = []
    public var unitsAreMetric = false
    public var experience: TrainingExperience?
    public var limitations: Set<PhysicalLimitation>?
    public var equipment: EquipmentAccess?
    /// Only manually supplied gaps. Exact birthday stays local and is never sent.
    public var healthDetails: HealthProfile?
    /// Whether they said they wear a watch to bed. Nil for anybody who onboarded before
    /// the question existed, which the record then answers on their behalf.
    public var wearsWatchToBed: Bool?

    public init() {}

    public var selectedGoals: Set<TrainingGoal> {
        goals ?? goal.map { [$0] } ?? []
    }

    public var orderedGoals: [TrainingGoal] {
        TrainingGoal.allCases.filter { selectedGoals.contains($0) }
    }

    public var impliesLifting: Bool { selectedGoals.contains { $0.impliesLifting } }

    public mutating func setGoals(_ selected: Set<TrainingGoal>) {
        goals = selected
        goal = orderedGoals.first
        if !impliesLifting { equipment = nil }
    }

    public var isComplete: Bool {
        guard !selectedGoals.isEmpty, frequency != nil, experience != nil, limitations != nil else { return false }
        return !impliesLifting || equipment != nil
    }

    /// Re-entering a flow must not erase details that its read-first UI omitted.
    public func preservingHealthDetails(from previous: OnboardingAnswers, today: Date = Date()) -> Self {
        var result = self
        result.healthDetails = healthDetails?.fillingMissing(from: previous.healthDetails ?? HealthProfile(), today: today)
            ?? previous.healthDetails?.sanitized(on: today)
        return result
    }

    public var limitationsText: String? {
        limitations.map { selected in
            PhysicalLimitation.allCases.filter { selected.contains($0) }.map(\.title).joined(separator: ", ")
        }
    }
}
