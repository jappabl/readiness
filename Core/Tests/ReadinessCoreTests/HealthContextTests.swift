import Foundation
import Testing
@testable import ReadinessCore

@Suite("Useful health context")
struct HealthContextTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        return calendar
    }
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 23))! }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
    private func build(_ values: [(Int, Double)]) -> HealthContext {
        .build(streams: [.init(name: "Steps", unit: "steps", observations: values.map {
            .init(date: day($0.0), value: $0.1)
        })], today: today, calendar: calendar)
    }

    @Test("Partial today is latest but never lowers the historical mean")
    func partialToday() {
        let metric = build([(-1, 8000), (-2, 6000), (0, 150)]).metrics.first!
        #expect(metric.latest == 150)
        #expect(metric.recordedOn == "2026-09-18")
        #expect(metric.mean7Days == 7000)
        #expect(metric.days7 == 2)
    }

    @Test("Missing is absent, an observed zero is preserved, and invalid values are ignored")
    func missingAndInvalid() {
        let metric = build([(-2, 10), (-1, 0), (0, .nan), (1, 100), (-3, .infinity), (-4, -5)]).metrics.first!
        #expect(metric.latest == 0)
        #expect(metric.daysAgo == 1)
        #expect(metric.mean7Days == 5)
        #expect(metric.days7 == 2)
        #expect(build([]).metrics.isEmpty)
    }

    @Test("Sparse old measurements keep their age and do not imply current coverage")
    func stale() {
        let context = build([(-30, 78.2)])
        #expect(context.metrics[0].daysAgo == 30)
        #expect(context.metrics[0].mean7Days == nil)
        #expect(context.metrics[0].mean28Days == nil)
        #expect(context.brief.contains("30d ago"))
        #expect(build([(-180, 50)]).metrics.isEmpty)
    }

    @Test("Window boundaries and duplicate days do not inflate coverage")
    func coverage() {
        let metric = build([(-28, 10), (-8, 20), (-7, 30), (-1, 40), (-1, 40)]).metrics[0]
        #expect(metric.days7 == 2)
        #expect(metric.mean7Days == 35)
        #expect(metric.days28 == 4)
        #expect(metric.mean28Days == 25)
    }

    @Test("The derived payload round trips without exporting the input history")
    func payload() throws {
        let context = build((0..<180).map { (-$0, Double($0)) })
        let data = try JSONEncoder().encode(context)
        #expect(try JSONDecoder().decode(HealthContext.self, from: data) == context)
        #expect(!String(decoding: data, as: UTF8.self).contains("observations"))
        #expect(data.count < 600)
    }
}

extension HealthContextTests {
    @Test("Activity-only context keeps real records and self report without inventing readiness")
    func noReadiness() throws {
        let health = build([(0, 2300), (-1, 8000)])
        let context = CoachContextBuilder.withoutReadiness(
            today: today, goal: "feelBetter", limitations: "Shoulder pain",
            checkIn: CheckIn(soreness: 4, energy: 2, stress: 1, mood: 3), acwr: nil,
            program: [], health: health)
        #expect(context.state == "unknown")
        #expect(context.confidence == "none")
        #expect(context.metrics.isEmpty)
        #expect(context.health?.metrics[0].latest == 2300)
        #expect(context.checkIn?["stress"] == 1)
        #expect(context.limitations == "Shoulder pain")
        #expect(context.brief.contains("stress 1=maxed,5=calm"))
        #expect(try JSONDecoder().decode(CoachContext.self, from: Data(context.json.utf8)) == context)
    }

    @Test("Old context JSON still decodes without a Health summary")
    func legacyPayload() throws {
        let context = CoachContextBuilder.withoutHealth(today: today, goal: "feelBetter")
        let json = try #require(context.json.data(using: .utf8))
        #expect(try JSONDecoder().decode(CoachContext.self, from: json).health == nil)
    }

    @Test("Health can be skipped and the whole onboarding still completes")
    func skipHealth() {
        var flow = OnboardingConversation()
        flow.toggleGoal(.feelBetter); flow.confirmGoals()
        flow.chooseFrequency(.rarely)
        flow.chooseExperience(.new)
        flow.confirmObstacles()
        flow.confirmLimitations(none: true)
        flow.chooseUnits(metric: true)
        flow.chooseWatch(wearsOne: true)
        flow.skipHealth()
        flow.skipHealthDetails()
        #expect(flow.step == .ready)
        #expect(flow.answers.goal == .feelBetter)
        #expect(flow.latestEditableAnswerID == nil)
    }
}

extension HealthContextTests {
    @Test("The coach header uses the same local date as the Health summary")
    func localDates() {
        let now = Date()
        let health = HealthContext.build(streams: [.init(name: "Steps", unit: "", observations: [.init(date: now, value: 100)])], today: now)
        let unknown = CoachContextBuilder.withoutReadiness(today: now, goal: nil, limitations: nil, checkIn: nil, acwr: nil, program: [], health: health)
        #expect(unknown.today == health.metrics[0].recordedOn)
        let readiness = ReadinessResult(state: .atBaseline, composite: 0, contributions: [], confidence: .normal, gateApplied: nil, modelVersion: ReadinessEngine.modelVersion)
        let measured = CoachContextBuilder.build(today: now, readiness: readiness, readings: [], daysOfHistory: 30,
            recommendation: RecommendationEngine.recommend(RecommendationInput(readiness: readiness)), checkIn: nil, acwr: nil,
            recentDays: [], program: [], goal: nil, limitations: nil, describe: { "\($0)" })
        #expect(measured.today == health.metrics[0].recordedOn)
    }
}
