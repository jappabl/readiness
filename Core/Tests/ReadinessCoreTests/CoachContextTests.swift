import Foundation
import Testing
@testable import ReadinessCore

private func sampleContext(days: Int = 14, exercises: Int = 6) -> CoachContext {
    let readings = MetricKind.allCases.map {
        MetricReading(kind: $0, value: 53.42719, baseline: 51.11837,
                      zScore: -1.28471, sampleCount: 60)
    }
    let contributions = MetricKind.allCases.map {
        InputContribution(kind: $0, zScore: -1.28471,
                          weight: ReadinessEngine.weights[$0] ?? 0, points: -0.4)
    }
    let readiness = ReadinessResult(state: .belowBaseline, composite: -1.28471,
                                    contributions: contributions, confidence: .normal,
                                    gateApplied: nil, modelVersion: ReadinessEngine.modelVersion)
    let recommendation = RecommendationEngine.recommend(
        RecommendationInput(readiness: readiness, checkIn: .neutral, acwr: 1.12))

    return CoachContextBuilder.build(
        today: Date(),
        readiness: readiness,
        readings: readings,
        daysOfHistory: 180,
        recommendation: recommendation,
        checkIn: .neutral,
        acwr: 1.12,
        recentDays: (0..<days).map {
            CoachContext.DaySummary(day: "2026-09-\(String(format: "%02d", $0 + 1))",
                                    state: "belowBaseline", composite: -0.8, volume: 12450)
        },
        program: (0..<exercises).map {
            CoachContext.ExerciseSummary(name: "Romanian deadlift \($0)", muscle: "hamstrings",
                                         sets: 3, reps: 8, weight: 185, rir: 2)
        },
        goal: "Add 20 lb to my squat by spring",
        limitations: "Left shoulder impingement on overhead pressing",
        describe: { "\($0)" })
}

@Suite("What leaves the device")
struct CoachContextTests {

    @Test("no raw sample or timeseries array is ever included")
    func carriesNoRawSamples() {
        let json = sampleContext().json
        for forbidden in ["samples", "timeseries", "heartRateSamples", "raw"] {
            #expect(!json.lowercased().contains(forbidden.lowercased()),
                    "context leaked a \(forbidden) field")
        }
    }

    @Test("a realistic day stays inside the context budget")
    func staysWithinBudget() {
        let bytes = sampleContext().approximateBytes
        #expect(bytes < 4096, "context was \(bytes) bytes; a flat price depends on this staying small")
    }

    @Test("history is capped, however much the user has")
    func historyIsCapped() {
        let context = sampleContext(days: 200)
        #expect(context.recentDays.count == CoachContext.maximumRecentDays)
    }

    @Test("values are rounded rather than carrying false precision")
    func valuesAreRounded() {
        let context = sampleContext()
        #expect(context.composite == -1.28)
        #expect(context.metrics.first?.value == 53.4)
        #expect(context.metrics.first?.z == -1.28)
    }

    @Test("what the user chose not to say is not invented")
    func emptyProfileFieldsAreOmitted() {
        let readings = [MetricReading(kind: .hrv, value: 50, baseline: 50, zScore: 0, sampleCount: 60)]
        let readiness = ReadinessResult(state: .atBaseline, composite: 0, contributions: [],
                                        confidence: .normal, gateApplied: nil,
                                        modelVersion: ReadinessEngine.modelVersion)
        let context = CoachContextBuilder.build(
            today: Date(), readiness: readiness, readings: readings, daysOfHistory: 60,
            recommendation: RecommendationEngine.recommend(RecommendationInput(readiness: readiness)),
            checkIn: nil, acwr: nil, recentDays: [], program: [],
            goal: "", limitations: nil, describe: { "\($0)" })
        #expect(context.goal == nil)
        #expect(context.limitations == nil)
        #expect(context.checkIn == nil)
    }

    @Test("the uncertainty the engine reported travels with the context")
    func uncertaintyTravels() {
        let context = sampleContext()
        #expect(!context.uncertainty.isEmpty || context.acwr != nil)
    }

    @Test("the context round-trips, so what is sent is what was built")
    func roundTrips() {
        let original = sampleContext()
        let data = original.json.data(using: .utf8) ?? Data()
        let decoded = try? JSONDecoder().decode(CoachContext.self, from: data)
        #expect(decoded == original)
    }
}
