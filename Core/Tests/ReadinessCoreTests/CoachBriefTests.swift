import Testing
import Foundation
@testable import ReadinessCore

/// The context is sent on every turn, so its size is a latency number as much as a
/// price one — every token of it has to be read before the first word comes back.
/// JSON spends most of its bytes repeating key names; this is the same facts, denser.
@Suite("The compact context")
struct CoachBriefTests {

    private func context(days: Int = 14, exercises: Int = 6) -> CoachContext {
        let readings = MetricKind.allCases.map {
            MetricReading(kind: $0, value: 53.4, baseline: 52.1, zScore: -1.23, sampleCount: 60)
        }
        let readiness = ReadinessEngine.evaluate(
            ReadinessInput(readings: readings, daysOfHistory: 180))
        let recommendation = RecommendationEngine.recommend(
            RecommendationInput(readiness: readiness, checkIn: .neutral, acwr: 1.1,
                                hasPlannedLowerBody: true))
        return CoachContextBuilder.build(
            today: Date(timeIntervalSince1970: 1_789_000_000),
            readiness: readiness, readings: readings, daysOfHistory: 180,
            recommendation: recommendation, checkIn: .neutral, acwr: 1.1,
            recentDays: (0..<days).map {
                CoachContext.DaySummary(day: "2026-09-\(String(format: "%02d", $0 + 1))",
                                        state: "maintain", composite: -0.31, volume: 12400)
            },
            program: (0..<exercises).map {
                CoachContext.ExerciseSummary(name: "Romanian deadlift \($0)",
                                             muscle: "hamstrings", sets: 3, reps: 5,
                                             weight: 185, rir: 2)
            },
            goal: "getStronger", limitations: "left shoulder, no overhead pressing",
            describe: { "\($0)" })
    }

    @Test("it is far smaller than the same facts as JSON")
    func muchSmallerThanJSON() {
        let ctx = context()
        let brief = ctx.brief.utf8.count
        let json = ctx.json.utf8.count
        #expect(Double(brief) < Double(json) * 0.6,
                "brief was \(brief) against \(json) as JSON; the saving has gone")
    }

    @Test("a realistic day stays inside the budget")
    func withinBudget() {
        let bytes = context().brief.utf8.count
        #expect(bytes < 1400, "brief was \(bytes) bytes")
    }

    @Test("every fact the coach is allowed to cite survives the compaction")
    func nothingImportantIsLost() {
        let ctx = context()
        let brief = ctx.brief

        #expect(brief.contains(ctx.state))
        #expect(brief.contains(ctx.confidence))
        #expect(brief.contains("180"), "days of history")
        for metric in ctx.metrics {
            #expect(brief.contains(metric.name), "\(metric.name) went missing")
            #expect(brief.contains(metric.unit), "\(metric.name)'s unit went missing")
        }
        for adjustment in ctx.proposedAdjustments {
            #expect(brief.contains(adjustment), "a proposed adjustment went missing")
        }
        for note in ctx.uncertainty {
            #expect(brief.contains(note), "an uncertainty note went missing")
        }
    }

    @Test("the programme survives with its loads")
    func programmeSurvives() {
        let brief = context().brief
        #expect(brief.contains("Romanian deadlift 0"))
        #expect(brief.contains("185"))
    }

    @Test("it still refuses to carry a raw sample or a timeseries")
    func carriesNoRawData() {
        let brief = context().brief.lowercased()
        for forbidden in ["samples", "timeseries", "heartratesamples", "raw"] {
            #expect(!brief.contains(forbidden), "\(forbidden) appeared in the context")
        }
    }

    @Test("the same context always renders identically, so a cache prefix can hold")
    func isDeterministic() {
        #expect(context().brief == context().brief)
    }
}
