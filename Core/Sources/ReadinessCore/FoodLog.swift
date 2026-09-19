import Foundation

public struct MealNutrition: Codable, Sendable, Equatable {
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public init(calories: Double, protein: Double, carbs: Double, fat: Double) {
        self.calories = calories; self.protein = protein; self.carbs = carbs; self.fat = fat
    }
    /// Reject malformed estimates and accidental non-finite/negative form values.
    public var isValid: Bool {
        calories.isFinite && (0...20000).contains(calories)
        && [protein, carbs, fat].allSatisfy { $0.isFinite && (0...2000).contains($0) }
    }
}

/// What a model said is in the photo.
///
/// Decoded leniently on purpose. This JSON is written by a language model, not by an
/// API we control, and models return the same meal a dozen different ways: macros
/// missing, numbers quoted as strings, nulls where a value was not known, a hedged
/// range instead of a figure. The strict version of this type threw all of those away
/// and showed one generic failure, so a photo of an avocado that had been read
/// perfectly well came back as "couldn't get a complete estimate".
///
/// Being generous here is safe because nothing is ever logged without the person
/// reading it back first. A missing macro becomes a zero they can correct, which is a
/// prompt rather than a claim.
public struct MealEstimate: Codable, Sendable {
    public var name: String
    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double

    public init(name: String, calories: Double, protein: Double = 0,
                carbs: Double = 0, fat: Double = 0) {
        self.name = name; self.calories = calories
        self.protein = protein; self.carbs = carbs; self.fat = fat
    }

    public var nutrition: MealNutrition {
        MealNutrition(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    /// The model looked and found no food. A different outcome from a broken response,
    /// and it deserves a different sentence on screen.
    public struct NoFoodFound: Error, Equatable { public init() {} }
    public struct InvalidEstimate: Error, Equatable { public init() {} }

    public static func decode(_ data: Data) throws -> MealEstimate {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw InvalidEstimate()
        }
        if object.isEmpty { throw NoFoodFound() }

        let name = (object["name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 160 else { throw InvalidEstimate() }
        // Calories are the one number the estimate exists to produce. Without it there
        // is nothing to review, so this stays strict.
        guard let calories = number(object["calories"]) else { throw InvalidEstimate() }

        let estimate = MealEstimate(name: name, calories: calories,
                                    protein: number(object["protein"]) ?? 0,
                                    carbs: number(object["carbs"]) ?? 0,
                                    fat: number(object["fat"]) ?? 0)
        guard estimate.nutrition.isValid else { throw InvalidEstimate() }
        return estimate
    }

    /// Accepts a number, a number written as a string, and a hedged range, which is
    /// read as its midpoint because a model that says "160-240" does know roughly what
    /// it is looking at.
    static func number(_ value: Any?) -> Double? {
        if let double = value as? Double { return double.isFinite ? double : nil }
        if let int = value as? Int { return Double(int) }
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }

        let parts = text.split(whereSeparator: { "-–—".contains($0) })
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            .filter(\.isFinite)
        if parts.count >= 2 { return (parts[0] + parts[1]) / 2 }
        if let only = parts.first { return only }

        // "240 kcal", "22 g" — take the leading figure and drop the unit.
        let digits = text.prefix { $0.isNumber || $0 == "." }
        return Double(digits).flatMap { $0.isFinite ? $0 : nil }
    }
}

public enum BodyMass {
    public static func display(kilograms: Double, metric: Bool) -> Double { metric ? kilograms : kilograms * 2.2046226218 }
    public static func kilograms(display: Double, metric: Bool) -> Double { metric ? display : display / 2.2046226218 }
    public static func isValid(kilograms: Double) -> Bool { kilograms.isFinite && (15...500).contains(kilograms) }
}


/// Decimal-pad entry must consume the whole field and cannot contain grouping.
public enum FoodNumber {
    public static func parse(_ text: String, decimalSeparator: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !decimalSeparator.isEmpty else { return nil }
        let separator = NSRegularExpression.escapedPattern(for: decimalSeparator)
        let pattern = "^[+-]?(?:[0-9]+(?:" + separator + "[0-9]*)?|" + separator + "[0-9]+)$"
        guard value.range(of: pattern, options: .regularExpression) != nil,
              let number = Double(value.replacingOccurrences(of: decimalSeparator, with: ".")),
              number.isFinite else { return nil }
        return number
    }
}
