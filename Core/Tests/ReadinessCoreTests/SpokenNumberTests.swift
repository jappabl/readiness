import Testing
@testable import ReadinessCore

/// Turning what people say into digits.
///
/// The parser used to know the words one to twenty and nothing else, so "ninety five
/// for twelve" found no weight at all and "two twenty five" became the digits 2, 20 and
/// 5 sitting next to each other, which the load reader then took the last of. A lifter
/// saying their working weight out loud is the single most common thing this has to
/// get right.
@Suite("Numbers said out loud")
struct SpokenNumberTests {

    private func expand(_ text: String) -> String { SpokenNumbers.expand(text) }

    @Test("the plain ones")
    func singleWords() {
        #expect(expand("five") == "5")
        #expect(expand("twelve") == "12")
        #expect(expand("twenty") == "20")
        #expect(expand("ninety") == "90")
    }

    @Test("tens and ones join up")
    func compoundTens() {
        #expect(expand("ninety five") == "95")
        #expect(expand("twenty two") == "22")
        #expect(expand("forty five") == "45")
    }

    @Test("hundreds")
    func hundreds() {
        #expect(expand("one hundred") == "100")
        #expect(expand("a hundred") == "100")
        #expect(expand("two hundred") == "200")
        #expect(expand("three hundred and fifteen") == "315")
        #expect(expand("two hundred twenty five") == "225")
        #expect(expand("a hundred and thirty five") == "135")
    }

    /// How lifters actually say a barbell weight: the hundreds digit, then the rest as
    /// a two-digit number, with the word "hundred" left out entirely.
    @Test("the way a gym says it")
    func lifterShorthand() {
        #expect(expand("two twenty five") == "225")
        #expect(expand("one thirty five") == "135")
        #expect(expand("three fifteen") == "315")
        #expect(expand("four oh five") == "405")
    }

    @Test("numbers keep the words around them")
    func inASentence() {
        #expect(expand("bench press two twenty five for eight")
                == "bench press 225 for 8")
        #expect(expand("three sets of ninety five") == "3 sets of 95")
    }

    @Test("digits already written stay as they are")
    func digitsPassThrough() {
        #expect(expand("225 for 8") == "225 for 8")
        #expect(expand("3x5 at 185") == "3x5 at 185")
    }

    @Test("a word that only looks like a number is left alone")
    func notEveryWordIsANumber() {
        // "oneself", "tensed": a naive replace inside words would wreck these, and the
        // feel vocabulary has to survive intact.
        #expect(expand("felt heavy") == "felt heavy")
        #expect(expand("tensed up") == "tensed up")
    }
}
