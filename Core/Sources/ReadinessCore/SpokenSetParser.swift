import Foundation

/// How a set felt. No sensor carries this, and no other lifting app collects it, which
/// is exactly why it is worth taking off messy speech.
public enum SetFeel: String, CaseIterable, Sendable, Codable {
    case easy, smooth, heavy, grindy, painful

    /// Words people actually say, mapped to the five buckets.
    static let vocabulary: [String: SetFeel] = [
        "easy": .easy, "light": .easy, "fast": .easy, "crisp": .easy, "snappy": .easy,
        "smooth": .smooth, "clean": .smooth, "good": .smooth, "solid": .smooth,
        "heavy": .heavy, "hard": .heavy, "slow": .heavy, "tough": .heavy,
        "grindy": .grindy, "grind": .grindy, "brutal": .grindy, "ugly": .grindy,
        "painful": .painful, "pain": .painful, "sharp": .painful, "tweaked": .painful,
    ]

    public var displayName: String { rawValue.capitalized }
}

/// The unit a weight was said in, when the sentence said one.
///
/// A bare "one hundred for five" means different weights in different gyms, so the
/// number alone is not enough to write down.
public enum SpokenLoadUnit: Sendable, Equatable {
    case pounds, kilograms
}

/// What the app understood from something the user said between sets.
public struct SpokenSetLog: Equatable, Sendable {
    public let exercise: String?
    public let reps: [Int]
    public let load: Double?
    /// Nil when the number was said on its own — the caller decides whose unit it is.
    public let loadUnit: SpokenLoadUnit?
    public let rir: Int?
    public let feel: SetFeel?
    /// Kept verbatim, so the user can always see what was heard.
    public let transcript: String

    public var isEmpty: Bool { reps.isEmpty && load == nil && feel == nil }
}

/// Turns "three sets of eight, six, seven, all to failure, felt heavy today" into
/// structured sets. Rest time is dead time; talking is the cheapest possible logger.
public enum SpokenSetParser {

    public static let maximumReasonableReps = 60
    public static let maximumReasonableLoad = 1500.0

    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
    ]

    public static func parse(_ transcript: String,
                             knownExercises: [String] = []) -> SpokenSetLog? {
        let raw = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        let text = normalised(raw)
        let heard = spokenLoad(in: text)
        let log = SpokenSetLog(
            exercise: exercise(in: raw, knownExercises: knownExercises),
            reps: reps(in: text),
            load: heard?.value,
            loadUnit: heard?.unit,
            rir: rir(in: text),
            feel: feel(in: text),
            transcript: raw)

        // Nothing loggable was said. Better to hear nothing than to invent a set.
        return log.isEmpty ? nil : log
    }

    /// Lower-cases and turns spoken numbers into digits, so one set of patterns
    /// handles "three sets of eight" and "3 sets of 8" alike.
    static func normalised(_ transcript: String) -> String {
        var text = transcript.lowercased()
        for (word, value) in numberWords {
            text = text.replacingOccurrences(
                of: "\\b\(word)\\b", with: String(value), options: .regularExpression)
        }
        return text
    }

    private static func matches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let r = Range(match.range(at: index), in: text) else { return "" }
                return String(text[r])
            }
        }
    }

    // MARK: - Reps

    static func reps(in text: String) -> [Int] {
        // "3 sets of 8, 6, 7": the list stops at the first word that is not a number
        // or a joiner, so "3 sets of 5 at 225" does not swallow the weight.
        if let match = matches(#"(\d+)\s+sets?\s+of\s+((?:\d+(?:\s*(?:,|and)\s*)?)+)"#,
                               in: text).first {
            let count = Int(match[1]) ?? 1
            let listed = numbers(in: match[2])
            if listed.count == 1, count > 1 { return Array(repeating: listed[0], count: count) }
            if !listed.isEmpty { return listed }
        }
        // "3x5"
        if let match = matches(#"(\d+)\s*(?:x|×|by)\s*(\d+)"#, in: text).first,
           let count = Int(match[1]), let value = Int(match[2]), valid(reps: value) {
            return Array(repeating: value, count: min(count, 20))
        }
        // "225 for 5", and "three sets of bench press at 165 for 5": said out loud the
        // lift's name lands between the two numbers, so the count is read on its own.
        if let match = matches(#"\bfor\s+(\d+)"#, in: text).first,
           let value = Int(match[1]), valid(reps: value) {
            return Array(repeating: value, count: setCount(in: text))
        }
        return []
    }

    /// How many sets were claimed, from anywhere in the sentence. One when nobody said.
    private static func setCount(in text: String) -> Int {
        guard let match = matches(#"(\d+)\s+sets?\b"#, in: text).first,
              let count = Int(match[1]), count > 0 else { return 1 }
        return min(count, 20)
    }

    private static func numbers(in text: String) -> [Int] {
        matches(#"\d+"#, in: text).compactMap { Int($0[0]) }.filter(valid(reps:))
    }

    private static func valid(reps: Int) -> Bool { reps > 0 && reps <= maximumReasonableReps }

    // MARK: - Load

    static func load(in text: String) -> Double? { spokenLoad(in: text)?.value }

    /// The weight, and the unit it was said in when one was said.
    ///
    /// Only the first pattern carries a unit. The other two are bare numbers, and
    /// reporting them as pounds would silently log a metric lifter 2.2× light.
    static func spokenLoad(in text: String) -> (value: Double, unit: SpokenLoadUnit?)? {
        if let match = matches(#"(\d+(?:\.\d+)?)\s*(pounds?|lbs?|kilos?|kilograms?|kgs?)\b"#,
                               in: text).first,
           let value = Double(match[1]), value > 0, value <= maximumReasonableLoad {
            let metric = match[2].hasPrefix("kilo") || match[2].hasPrefix("kg")
            return (value, metric ? .kilograms : .pounds)
        }
        for pattern in [#"\bat\s+(\d+(?:\.\d+)?)"#, #"(\d+(?:\.\d+)?)\s+for\s+\d"#] {
            if let match = matches(pattern, in: text).first, let value = Double(match[1]),
               value > 0, value <= maximumReasonableLoad {
                return (value, nil)
            }
        }
        return nil
    }

    // MARK: - Effort

    static func rir(in text: String) -> Int? {
        if !matches(#"\b(?:to|till|until)\s+failure\b|\ball\s+out\b|\bmaxed\s+out\b"#,
                    in: text).isEmpty {
            return 0
        }
        if let match = matches(
            #"(\d+)\s*(?:reps?\s*)?(?:in\s+(?:the\s+)?(?:tank|reserve)|\brir\b)"#,
            in: text).first, let value = Int(match[1]), (0...10).contains(value) {
            return value
        }
        return nil
    }

    // MARK: - Feel

    static func feel(in text: String) -> SetFeel? {
        var best: (index: String.Index, feel: SetFeel)?
        for (word, feel) in SetFeel.vocabulary {
            guard let found = matches(#"\b\#(word)\b"#, in: text).first, !found[0].isEmpty,
                  let range = text.range(of: found[0]) else { continue }
            if best == nil || range.lowerBound < best!.index {
                best = (range.lowerBound, feel)
            }
        }
        return best?.feel
    }

    // MARK: - Exercise

    /// Only ever one of the user's own lifts. Naming a movement they do not train
    /// would be inventing data.
    static func exercise(in transcript: String, knownExercises: [String]) -> String? {
        let haystack = transcript.lowercased()
        return knownExercises
            .filter { haystack.contains($0.lowercased()) }
            .max { $0.count < $1.count }
    }
}
