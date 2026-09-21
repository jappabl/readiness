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
    /// Nil when the number was said on its own: the caller decides whose unit it is.
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
        let counted = reps(in: text)
        let heard = spokenLoad(in: text, repsAreKnown: !counted.isEmpty)
        let log = SpokenSetLog(
            exercise: exercise(in: raw, knownExercises: knownExercises),
            reps: counted,
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
        // Whole runs of number words at a time, so "two twenty five" becomes 225 rather
        // than the three separate digits a word-by-word replace used to leave behind.
        SpokenNumbers.expand(transcript.lowercased())
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

    /// The effort phrase removed, so its number cannot be mistaken for a rep count.
    ///
    /// "225 for 5, 3 RIR" was being read as two sets, of five and of three. The three
    /// is how much was left in the tank, and it has to stop being a number before
    /// anything goes looking for a list.
    static func withoutEffort(_ text: String) -> String {
        var cleaned = text
        for pattern in [#"\d+\s*(?:reps?\s*)?in\s+(?:the\s+)?(?:tank|reserve)"#,
                        #"\d+\s*rir\b"#, #"\brir\s*\d+"#] {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: " ",
                                                   options: [.regularExpression])
        }
        return cleaned
    }

    static func reps(in raw: String) -> [Int] {
        let text = withoutEffort(raw)

        // "225 x 8" is not 225 sets. A count that large is the weight, and whichever
        // side cannot be a set count says which reading this is.
        if let match = matches(#"(\d+)\s*(?:x|×|by)\s*(\d+)"#, in: text).first,
           let left = Int(match[1]), let right = Int(match[2]), valid(reps: right) {
            if left <= maximumReasonableSets { return Array(repeating: right, count: left) }
            return [right]
        }
        // "six reps", "6 reps each", "6 reps per": out loud, the commonest way to say it.
        if let match = matches(#"(\d+)\s*reps?\b"#, in: text).first,
           let value = Int(match[1]), valid(reps: value) {
            return Array(repeating: value, count: setCount(in: text))
        }
        // "3 sets of 8, 6, 7", and "a set of 10", and "three sets 10, 9, 8" with no
        // "of" in it at all. The list stops at the first word that is not a number or a
        // joiner, so "3 sets of 5 at 225" does not swallow the weight.
        if let match = matches(#"(?:(\d+)\s+)?(?:a\s+)?sets?\s+(?:of\s+)?((?:\d+(?:\s*(?:,|and)\s*)?)+)"#,
                               in: text).first {
            let count = Int(match[1]) ?? 1
            let listed = numbers(in: match[2])
            if listed.count == 1, count > 1 { return Array(repeating: listed[0], count: count) }
            if !listed.isEmpty { return listed }
        }
        // "225 for 5", and "three sets of bench press at 165 for 5": said out loud the
        // lift's name lands between the two numbers, so the count is read on its own.
        if let match = matches(#"\bfor\s+((?:\d+(?!\s*sets?\b)(?:\s*(?:,|and)\s*)?)+)"#,
                               in: text).first {
            let listed = numbers(in: match[1])
            if listed.count > 1 { return listed }
            if let only = listed.first {
                return Array(repeating: only, count: setCount(in: text))
            }
        }
        // "8 at 225", "just did 8 at 225", "8, 8, 7 at 225". The number before "at" is
        // the reps and the one after it is the weight, which is the opposite way round
        // from every pattern above.
        if let match = matches(#"((?:\d+(?!\s*sets?\b)(?:\s*(?:,|and)\s*)?)+)\s*at\s+\d"#,
                               in: text).first {
            let listed = numbers(in: match[1])
            if listed.count > 1 { return listed }
            if let only = listed.first {
                return Array(repeating: only, count: setCount(in: text))
            }
        }
        // Nothing marked at all: "bench press, 225, 8", "10 pull-ups". Whatever is left
        // that could be a rep count is one, and anything too big to be is the weight.
        //
        // The set count is not up for grabs here. "3 sets of 225" states a count and a
        // weight and no reps at all, and reading the 3 as a rep count would invent
        // three sets of three.
        var loose = matches(#"\d+"#, in: text).compactMap { Int($0[0]) }
        if let spoken = matches(#"(\d+)\s+sets?\b"#, in: text).first,
           let count = Int(spoken[1]), let claimed = loose.firstIndex(of: count) {
            loose.remove(at: claimed)
        }
        let plausible = loose.filter(valid(reps:))
        if !plausible.isEmpty, loose.count <= 3 {
            return Array(repeating: plausible[plausible.count - 1], count: setCount(in: text))
        }
        return []
    }

    /// Above this a number said before "sets" or beside an x is a weight rather than a
    /// count. Nobody does thirty sets, and 225 x 8 is one set of eight.
    static let maximumReasonableSets = 20

    /// How many sets were claimed, from anywhere in the sentence. One when nobody said.
    private static func setCount(in text: String) -> Int {
        guard let match = matches(#"(\d+)\s+sets?\b"#, in: text).first,
              let count = Int(match[1]), count > 0 else { return 1 }
        return min(count, maximumReasonableSets)
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
    static func spokenLoad(in text: String, repsAreKnown: Bool = false) -> (value: Double, unit: SpokenLoadUnit?)? {
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
        // "3 sets of 155 of bench press". The weight is sitting where a rep count
        // usually goes, and nobody does 155 reps, so the number itself says which it
        // is. Without this the whole sentence parsed to nothing: the rep reader
        // discarded 155 as implausible and no load pattern matched, because there
        // was no "at" and no "for" anywhere in it.
        if let match = matches(#"\d+\s+sets?\s+of\s+(\d+(?:\.\d+)?)"#, in: text).first,
           let value = Double(match[1]), !valid(reps: Int(value)),
           value > 0, value <= maximumReasonableLoad {
            return (value, nil)
        }
        // Last resort, and only once the reps are accounted for: a number nothing else
        // claimed, too big to be a rep count and small enough to be a barbell. "back
        // squat 5 reps 315" marks 315 as nothing at all. Requiring the reps first is
        // what keeps this honest, since on its own it would read "felt heavy after 90
        // minutes" as ninety pounds.
        if repsAreKnown,
           let found = matches(#"(\d+(?:\.\d+)?)"#, in: text)
            .compactMap({ Double($0[1]) })
            .first(where: { !valid(reps: Int($0)) && $0 > 0 && $0 <= maximumReasonableLoad }) {
            return (found, nil)
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
