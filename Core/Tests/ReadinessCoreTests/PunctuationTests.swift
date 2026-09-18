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

    @Test("no onboarding copy uses one")
    func onboarding() {
        check(TrainingFrequency.allCases.flatMap { [$0.title, $0.detail] }, "TrainingFrequency")
        check(Obstacle.allCases.map(\.title), "Obstacle")
    }
}
