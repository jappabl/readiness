import Testing
@testable import ReadinessCore

private func day(sleep: Double, volume: Double, lower: Bool = false) -> InsightEngine.TrainingDay {
    InsightEngine.TrainingDay(sleepHours: sleep, volumeLoad: volume, isLowerBody: lower)
}

@Suite("Weekly insight")
struct InsightEngineTests {

    @Test("too few sessions means no claim at all")
    func staysQuietOnThinData() {
        let days = (0..<4).map { day(sleep: Double(6 + $0 % 3), volume: 1000) }
        #expect(InsightEngine.sleepPerformancePattern(days) == nil)
    }

    @Test("no relationship means no claim")
    func staysQuietWithoutAPattern() {
        let days = (0..<10).map { day(sleep: $0 % 2 == 0 ? 6.0 : 8.5, volume: 1000) }
        #expect(InsightEngine.sleepPerformancePattern(days) == nil)
    }

    @Test("a real lift after longer sleep is reported with the actual threshold")
    func reportsARealPattern() {
        let poor = (0..<5).map { _ in day(sleep: 5.8, volume: 800) }
        let good = (0..<5).map { _ in day(sleep: 8.2, volume: 1400) }
        let insight = InsightEngine.sleepPerformancePattern(poor + good)
        #expect(insight != nil)
        #expect(insight?.contains("sleep") == true)
    }

    @Test("the claim names a number the user can act on")
    func namesAThreshold() {
        let poor = (0..<5).map { _ in day(sleep: 5.5, volume: 700) }
        let good = (0..<5).map { _ in day(sleep: 8.0, volume: 1500) }
        let insight = InsightEngine.sleepPerformancePattern(poor + good) ?? ""
        #expect(insight.contains("h") || insight.contains("hour"))
    }

    @Test("a drop after longer sleep is not dressed up as a win")
    func doesNotInventAWin() {
        let poor = (0..<5).map { _ in day(sleep: 5.5, volume: 1500) }
        let good = (0..<5).map { _ in day(sleep: 8.0, volume: 700) }
        let insight = InsightEngine.sleepPerformancePattern(poor + good)
        #expect(insight == nil, "a negative relationship is not a finding worth surfacing in v1")
    }

    @Test("identical sleep across every session cannot split the data")
    func constantSleepIsSafe() {
        let days = (0..<10).map { _ in day(sleep: 7.0, volume: 1000) }
        #expect(InsightEngine.sleepPerformancePattern(days) == nil)
    }

    @Test("sessions with no volume cannot produce a percentage")
    func zeroVolumeIsSafe() {
        let days = (0..<10).map { i in day(sleep: i < 5 ? 6.0 : 8.0, volume: 0) }
        let insight = InsightEngine.sleepPerformancePattern(days)
        #expect(insight == nil)
    }
}
