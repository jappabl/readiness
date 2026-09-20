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

    /// The popover beside "Sleep debt" describes how the balance is built, and it has
    /// twice gone on describing a model that had been replaced underneath it: it claimed
    /// a fortnight after the window became a week, and it claimed the reference was the
    /// top of your own distribution after that reference became a median floored at
    /// seven hours. Both are checkable claims, and a user who checks finds the number on
    /// the card disagrees with the sentence explaining it — a weekday-6.5/weekend-9
    /// sleeper's "longest nights" imply roughly 22 hours owed against a card reading 0.
    @Test("the sleep-debt explanation describes the model that is actually running")
    func debtExplanationTracksTheModel() {
        let text = MetricKind.sleepDebt.explanation.lowercased()

        #expect(SleepDebt.window == 7,
                "the window moved; this explanation and this test both need rewording")
        #expect(!text.contains("two weeks") && !text.contains("fortnight"),
                "says a fortnight, but the balance looks back \(SleepDebt.window) nights")
        // "The last week" was itself wrong, if more subtly: the window counts *recorded*
        // nights, so at four nights of watch wear a week it spans twelve calendar days.
        #expect(text.contains("seven nights"), "never says how far back it looks")
        #expect(!text.contains("last week"), "counts nights, not days")

        // `SleepDebt.reference(for:)` is the median floored at `learnedFloorHours`.
        // `SleepNeed`'s upper-percentile need is a different quantity for a different
        // question, and the two were conflated here.
        #expect(!text.contains("longest night"),
                "claims an upper-percentile reference; the balance accrues against a median")
    }
}
