import Testing
@testable import ReadinessCore

/// Guards the rule that a contribution's sign and its measurement's direction are
/// different things. An elevated resting heart rate hurts readiness *and* is above
/// baseline; describing it as "below" is a factual error in the evidence the product
/// promises to show.
@Suite("Contribution sign versus measurement direction")
struct DirectionTests {

    @Test("an inverted metric contributes negatively while reading above baseline")
    func invertedMetricDivergesFromItsContribution() {
        let raised = MetricReading(kind: .restingHeartRate, value: 70, baseline: 53,
                                   zScore: 3.2, sampleCount: 60)
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: [raised], daysOfHistory: 60))
        let contribution = result.contributions.first

        #expect((contribution?.points ?? 0) < 0, "a raised resting heart rate should hurt")
        #expect((contribution?.zScore ?? 0) > 0, "...while the measurement is above baseline")
    }

    @Test("a direct metric agrees with its contribution")
    func directMetricAgreesWithItsContribution() {
        let lowHRV = MetricReading(kind: .hrv, value: 20, baseline: 53,
                                   zScore: -2.5, sampleCount: 60)
        let result = ReadinessEngine.evaluate(
            ReadinessInput(readings: [lowHRV], daysOfHistory: 60))
        let contribution = result.contributions.first
        #expect((contribution?.points ?? 0) < 0)
        #expect((contribution?.zScore ?? 0) < 0)
    }

    @Test("every metric's polarity is the sign that relates the two")
    func polarityRelatesThem() {
        for kind in MetricKind.allCases {
            let reading = MetricReading(kind: kind, value: 0, baseline: 0,
                                        zScore: 1.0, sampleCount: 60)
            let result = ReadinessEngine.evaluate(
                ReadinessInput(readings: [reading], daysOfHistory: 60))
            let points = result.contributions.first?.points ?? 0
            #expect((points > 0) == (kind.polarity > 0),
                    "\(kind) contribution sign does not match its polarity")
        }
    }
}
