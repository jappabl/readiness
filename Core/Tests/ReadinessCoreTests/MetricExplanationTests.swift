import Testing
@testable import ReadinessCore

/// A number nobody understands is decoration. Every metric the app puts on screen has
/// to be able to say what it is.
@Suite("Explaining a metric")
struct MetricExplanationTests {

    @Test("every metric explains itself")
    func allKindsAreExplained() {
        for kind in MetricKind.allCases {
            #expect(!kind.explanation.isEmpty, "\(kind.rawValue) has nothing to say")
            #expect(kind.explanation.count > 80,
                    "\(kind.rawValue) is too short to actually explain anything")
        }
    }

    @Test("an explanation never diagnoses or prescribes")
    func staysOutOfTheClinic() {
        // The app is not a clinician and the wording is the only thing stopping a
        // plain-language explainer from reading like one.
        let banned = ["disease", "diagnos", "symptom", "you should take",
                      "treat", "cure", "condition", "disorder"]
        for kind in MetricKind.allCases {
            let text = kind.explanation.lowercased()
            for phrase in banned {
                #expect(!text.contains(phrase),
                        "\(kind.rawValue) says \"\(phrase)\"")
            }
        }
    }

    @Test("each explanation says which direction is which")
    func namesADirection() {
        for kind in MetricKind.allCases {
            let text = kind.explanation.lowercased()
            #expect(text.contains("higher") || text.contains("lower")
                    || text.contains("up") || text.contains("down")
                    || text.contains("short") || text.contains("rise"),
                    "\(kind.rawValue) never says what a move means")
        }
    }
}
