import Testing
@testable import ReadinessCore

/// Em dashes read as machine-written, so the product does not use them. A comma, a full
/// stop, or a new sentence does the same job without the tell.
@Suite("Punctuation the product does not use")
struct PunctuationTests {

    private func check(_ strings: [String], _ source: String) {
        for text in strings {
            #expect(!text.contains("—"), "em dash in \(source): \"\(text)\"")
            #expect(!text.contains("--"), "double hyphen standing in for one in \(source)")
        }
    }

    @Test("no metric copy uses one")
    func metrics() {
        check(MetricKind.allCases.flatMap { [$0.displayName, $0.unit, $0.explanation] },
              "MetricKind")
    }

    @Test("no goal copy uses one")
    func goals() {
        check(TrainingGoal.allCases.flatMap { [$0.title, $0.promise] }, "TrainingGoal")
    }

    /// The sweep went through the copy that is written down. This one is assembled at
    /// runtime, so it was never a string anybody could grep, and it survived: the day
    /// sheet reads "Lifting pushed it up most \u{2014} 1 hard set."
    @Test("nor a sentence the engine builds itself")
    func assembledSummaries() {
        func score(_ contributor: ScoreContributor) -> SignalScore {
            SignalScore(kind: .strain, value: 42, band: .yellow, contributors: [contributor],
                        coverage: .full, modelVersion: "test")
        }
        let withComparison = ScoreContributor(
            id: "lifting", title: "Lifting", value: 1, unit: "hard set",
            comparison: 3, comparisonLabel: "your usual", state: .fine,
            magnitude: 12, explanation: "")
        let bareValue = ScoreContributor(
            id: "lifting", title: "Lifting", value: 1, unit: "hard set",
            comparison: nil, comparisonLabel: nil, state: .fine,
            magnitude: 12, explanation: "")
        check([score(withComparison).summary, score(bareValue).summary], "SignalScore.summary")
    }

    @Test("no onboarding copy uses one")
    func onboarding() {
        check(TrainingFrequency.allCases.flatMap { [$0.title, $0.detail] }, "TrainingFrequency")
        check(Obstacle.allCases.map(\.title), "Obstacle")
    }
}
