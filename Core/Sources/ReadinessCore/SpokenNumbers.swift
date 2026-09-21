import Foundation

/// Numbers as people say them, turned into digits.
///
/// Split out from `SpokenSetParser` because it is the piece everything else depends on:
/// no pattern for reps or load can match a weight that is still four English words. The
/// old version knew one to twenty and nothing more, so "ninety five for twelve" found no
/// weight at all, and "two twenty five" arrived as the separate digits 2, 20 and 5.
///
/// Handles ordinary English (ninety five, three hundred and fifteen) and the shorthand a
/// gym actually uses, where the hundreds digit is said and the word "hundred" is not:
/// two twenty five, one thirty five, four oh five.
public enum SpokenNumbers {

    static let ones: [String: Int] = [
        "zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19,
    ]

    static let tens: [String: Int] = [
        "twenty": 20, "thirty": 30, "forty": 40, "fourty": 40, "fifty": 50,
        "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    /// Words that join a number without being one: "a hundred and thirty five".
    static let joiners: Set<String> = ["and"]

    public static func expand(_ text: String) -> String {
        let pieces = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var run: [String] = []

        func flush() {
            guard !run.isEmpty else { return }
            // A trailing joiner belongs to the sentence rather than to the number.
            while let last = run.last, joiners.contains(strip(last)) {
                run.removeLast()
                out.append(last)
            }
            guard !run.isEmpty else { return }
            if let value = value(of: run.map(strip)) {
                // Punctuation riding on the last word comes with it, so
                // "two twenty five, felt heavy" keeps its comma.
                out.append("\(value)" + trailingPunctuation(run[run.count - 1]))
            } else {
                // Not one number together, so read them one at a time. "eight six
                // seven" is three rep counts, not a failed attempt at a single value.
                for word in run {
                    if let single = ones[strip(word)] ?? tens[strip(word)] {
                        out.append("\(single)" + trailingPunctuation(word))
                    } else {
                        out.append(word)
                    }
                }
            }
            run = []
        }

        for index in pieces.indices {
            let piece = pieces[index]
            let word = strip(piece)
            // "a" is only a number when "hundred" is the next word.
            let indefiniteHundred = word == "a"
                && index + 1 < pieces.count && strip(pieces[index + 1]) == "hundred"
            if isNumberWord(word) || indefiniteHundred
                || (joiners.contains(word) && !run.isEmpty) {
                run.append(piece)
                // A comma ends the number. "eight, six, seven" is three of them, and
                // running them together made one value that was none of the three.
                if piece.contains(",") { flush() }
            } else {
                flush()
                out.append(piece)
            }
        }
        flush()
        return out.joined(separator: " ")
    }

    private static func isNumberWord(_ word: String) -> Bool {
        // "a" is not a number on its own. It only counts inside a run, where the value
        // reader turns "a hundred" into one hundred.
        ones[word] != nil || tens[word] != nil || word == "hundred"
    }

    private static func strip(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private static func trailingPunctuation(_ word: String) -> String {
        let trimmed = word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let range = word.range(of: trimmed) else { return "" }
        return String(word[range.upperBound...])
    }

    /// One run of number words as a single value, or nil when they do not make one.
    static func value(of words: [String]) -> Int? {
        let parts = words.filter { !joiners.contains($0) && $0 != "a" }
        guard !parts.isEmpty else { return nil }

        // "a hundred" only counts when "hundred" follows it.
        var terms: [Int] = []
        var index = 0
        // "a hundred" is one hundred. Dropping the article here means the hundred
        // branch below finds no digit in front of it and supplies one itself.
        var total = 0
        var sawHundred = false
        while index < parts.count {
            let word = parts[index]
            if word == "hundred" {
                // The digit before it multiplies, or it stands for one hundred alone.
                let leading = terms.popLast() ?? 1
                total += leading * 100
                sawHundred = true
            } else if let value = ones[word] ?? tens[word] {
                terms.append(value)
            } else {
                return nil
            }
            index += 1
        }

        if sawHundred {
            return total + terms.reduce(0, +)
        }
        return combine(terms)
    }

    /// A run with no "hundred" in it.
    ///
    /// Two shapes. Ordinary English is a tens word and then a ones word: ninety five.
    /// The gym's shorthand is a digit, then a two-digit number, with "hundred" simply
    /// omitted: two twenty five, one thirty five, four oh five. Both are unambiguous
    /// from the shape of the values themselves.
    private static func combine(_ terms: [Int]) -> Int? {
        switch terms.count {
        case 0: return nil
        case 1: return terms[0]
        case 2:
            let (first, second) = (terms[0], terms[1])
            // ninety five
            if first >= 20, second < 10 { return first + second }
            // two twenty, three fifteen
            if first < 10, second >= 10 { return first * 100 + second }
            // two five, meaning nothing in particular
            return nil
        case 3:
            // four oh five, two twenty five
            let (first, second, third) = (terms[0], terms[1], terms[2])
            guard first < 10 else { return nil }
            if second == 0 { return first * 100 + third }
            if second >= 20, third < 10 { return first * 100 + second + third }
            return nil
        default:
            return nil
        }
    }
}
