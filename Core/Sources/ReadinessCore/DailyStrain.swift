import Foundation

/// Observed daily totals only. A nil value means unavailable, never a rest day.
public struct DailyActivity: Sendable, Equatable {
    public let date: Date
    public let activeEnergyKcal: Double?
    public let exerciseMinutes: Double?
    public let steps: Double?
    public let workoutEnergyKcal: Double?
    public let workoutMinutes: Double?

    public init(date: Date, activeEnergyKcal: Double? = nil, exerciseMinutes: Double? = nil,
                steps: Double? = nil, workoutEnergyKcal: Double? = nil, workoutMinutes: Double? = nil) {
        self.date = date
        self.activeEnergyKcal = activeEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.steps = steps
        self.workoutEnergyKcal = workoutEnergyKcal
        self.workoutMinutes = workoutMinutes
    }

    fileprivate func value(for metric: DailyStrainMetric) -> Double? {
        let value: Double?
        switch metric {
        case .activeEnergy: value = activeEnergyKcal
        case .exerciseMinutes: value = exerciseMinutes
        case .steps: value = steps
        case .workoutEnergy: value = workoutEnergyKcal
        case .workoutMinutes: value = workoutMinutes
        }
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }
}

public enum DailyStrainMetric: String, Sendable, Equatable, CaseIterable {
    case activeEnergy, exerciseMinutes, steps, workoutEnergy, workoutMinutes

    public var label: String {
        switch self {
        case .activeEnergy: "Active energy"
        case .exerciseMinutes: "Exercise time"
        case .steps: "Steps"
        case .workoutEnergy: "Workout energy"
        case .workoutMinutes: "Workout time"
        }
    }
    public var unit: String {
        switch self {
        case .activeEnergy, .workoutEnergy: "kcal"
        case .exerciseMinutes, .workoutMinutes: "min"
        case .steps: "steps"
        }
    }
    public var isWorkoutOnly: Bool { self == .workoutEnergy || self == .workoutMinutes }
}

public enum DailyStrainCoverage: Sendable, Equatable {
    case relativeToHistory, buildingBaseline, recordedZero
}

public struct DailyStrainResult: Sendable, Equatable {
    public let percent: Int?
    public let metric: DailyStrainMetric
    public let value: Double
    public let baselineDays: Int
    public let coverage: DailyStrainCoverage

    public var summary: String {
        let amount = value.formatted(.number.precision(.fractionLength(0)))
        let source = metric.isWorkoutOnly ? "Recorded Health workouts only" : "Recorded Health \(metric.label.lowercased())"
        if coverage == .recordedZero {
            return "\(source): 0 \(metric.unit) today. Zero recorded does not establish full-day coverage."
        }
        guard let percent else {
            return "\(source): \(amount) \(metric.unit) today. \(baselineDays) of 7 prior days available for a personal comparison."
        }
        return "\(amount) \(metric.unit) so far today, at percentile \(percent) against \(baselineDays) prior recorded days for \(metric.label.lowercased()). Today is still in progress."
    }
}

/// A descriptive activity percentile, not a physiological strain or safety model.
/// Active energy already includes exercise: workout energy is a fallback, never an addend.
/// https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned
public enum DailyStrain {
    public static let minimumBaselineDays = 7
    public static let historyDays = 28

    public static func evaluate(days: [DailyActivity], on date: Date = Date(),
                                calendar: Calendar = .current) -> DailyStrainResult? {
        let today = calendar.startOfDay(for: date)
        guard let cutoff = calendar.date(byAdding: .day, value: -historyDays, to: today) else { return nil }
        // At most one aggregate per local date; use the latest available update.
        var byDay: [Date: DailyActivity] = [:]
        for day in days where day.date <= date {
            let key = calendar.startOfDay(for: day.date)
            guard key >= cutoff, key <= today else { continue }
            if let previous = byDay[key], previous.date > day.date { continue }
            byDay[key] = day
        }
        guard let current = byDay[today] else { return nil }
        // Preserve the most complete available signal rather than switching based on
        // its numeric value or summing unrelated units. Fallback coverage is labeled.
        let priority: [DailyStrainMetric] = [.activeEnergy, .exerciseMinutes, .steps, .workoutEnergy, .workoutMinutes]
        guard let metric = priority.first(where: { current.value(for: $0) != nil }),
              let value = current.value(for: metric) else { return nil }
        let history = byDay.filter { $0.key < today }.values.compactMap { $0.value(for: metric) }
        if value == 0 {
            return .init(percent: 0, metric: metric, value: value,
                         baselineDays: history.count, coverage: .recordedZero)
        }
        guard history.count >= minimumBaselineDays else {
            return .init(percent: nil, metric: metric, value: value,
                         baselineDays: history.count, coverage: .buildingBaseline)
        }
        let lower = history.filter { $0 < value }.count
        let equal = history.filter { $0 == value }.count
        let percentile = (Double(lower) + Double(equal) / 2) / Double(history.count) * 100
        return .init(percent: Int(percentile.rounded()), metric: metric, value: value,
                     baselineDays: history.count, coverage: .relativeToHistory)
    }
}
