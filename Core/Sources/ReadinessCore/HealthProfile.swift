import Foundation

/// Characteristics stay separate from dated daily measurements. Missing is unknown.
public struct HealthProfile: Codable, Sendable, Equatable {
    public enum BiologicalSex: String, Codable, Sendable, CaseIterable {
        case female, male, other
        public var title: String { rawValue.capitalized }
    }
    public enum Field: Sendable, Equatable { case height, dateOfBirth, biologicalSex }

    public var heightCM: Double?
    public var dateOfBirth: DateComponents?
    public var biologicalSex: BiologicalSex?

    public init(heightCM: Double? = nil, dateOfBirth: DateComponents? = nil, biologicalSex: BiologicalSex? = nil) {
        self.heightCM = heightCM
        self.dateOfBirth = dateOfBirth
        self.biologicalSex = biologicalSex
    }

    public func ageYears(on today: Date = Date()) -> Int? {
        guard let parts = dateOfBirth, let year = parts.year, let month = parts.month, let day = parts.day else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(year: year, month: month, day: day)
        guard let birth = calendar.date(from: components), birth <= today,
              calendar.dateComponents([.year, .month, .day], from: birth) == components,
              let age = calendar.dateComponents([.year], from: birth, to: today).year,
              (0...120).contains(age) else { return nil }
        return age
    }

    public func sanitized(on today: Date = Date()) -> HealthProfile {
        HealthProfile(heightCM: heightCM.flatMap { $0.isFinite && (40...250).contains($0) ? $0 : nil },
                      dateOfBirth: ageYears(on: today) == nil ? nil : dateOfBirth,
                      biologicalSex: biologicalSex)
    }

    public func isValid(on today: Date = Date()) -> Bool { sanitized(on: today) == self }

    public func missingFields(on today: Date = Date()) -> [Field] {
        let valid = sanitized(on: today)
        var result: [Field] = []
        if valid.heightCM == nil { result.append(.height) }
        if valid.dateOfBirth == nil { result.append(.dateOfBirth) }
        if valid.biologicalSex == nil { result.append(.biologicalSex) }
        return result
    }

    public func fillingMissing(from fallback: HealthProfile, today: Date = Date()) -> HealthProfile {
        let read = sanitized(on: today), manual = fallback.sanitized(on: today)
        return HealthProfile(heightCM: read.heightCM ?? manual.heightCM,
                             dateOfBirth: read.dateOfBirth ?? manual.dateOfBirth,
                             biologicalSex: read.biologicalSex ?? manual.biologicalSex)
    }
}

/// The provider gets an age, never birth date components or the raw answer JSON.
public struct CoachProfileSummary: Codable, Sendable, Equatable {
    public let ageYears: Int?
    public let heightCM: Double?
    public let biologicalSex: HealthProfile.BiologicalSex?
    public let experience: TrainingExperience?
    public let equipment: EquipmentAccess?
    public let allowedExercises: [String]?

    public init(health: HealthProfile, answers: OnboardingAnswers, limitations: String? = nil, today: Date = Date()) {
        let health = health.sanitized(on: today)
        ageYears = health.ageYears(on: today)
        heightCM = health.heightCM
        biologicalSex = health.biologicalSex
        experience = answers.experience
        equipment = answers.equipment
        let restrictions: Set<PhysicalLimitation>?
        if let limitations { restrictions = PhysicalLimitation.from(profileText: limitations) }
        else { restrictions = answers.limitations ?? [] }
        allowedExercises = answers.equipment.map {
            StarterPrograms.allowedExerciseNames(equipment: $0, limitations: restrictions)
        }
    }

    public var brief: String {
        var lines: [String] = []
        if let ageYears { lines.append("age \(ageYears) years") }
        if let heightCM { lines.append("height \(heightCM) cm") }
        if let biologicalSex { lines.append("biological sex \(biologicalSex.rawValue)") }
        if let experience {
            lines.append("training experience \(experience.rawValue); \(experience.detail)")
            if equipment != nil { lines.append("progression: \(experience.progression.guidance)") }
        }
        if let equipment { lines.append("equipment: \(equipment.title)") }
        if let allowedExercises {
            lines.append("allowed starter exercises/substitutions: " + (allowedExercises.isEmpty ? "none; do not invent a safe alternative" : allowedExercises.joined(separator: ", ")))
        }
        return lines.joined(separator: "\n")
    }
}
