import Testing
@testable import ReadinessCore

@Suite("Baseline — today against the user's own rolling history")
struct BaselineEngineTests {

    @Test("a value sitting on the baseline mean scores zero")
    func onBaselineIsZero() {
        let series = Array(repeating: 50.0, count: 30) + [50.0]
        let result = BaselineEngine.evaluate(series: series)
        #expect(result != nil)
        #expect(abs(result?.zScore ?? 9) < 1e-9)
    }

    @Test("a value one standard deviation above baseline scores one")
    func oneSDAboveScoresOne() {
        // Prior days alternate 40/60: mean 50, population SD 10.
        let prior = Array(repeating: [40.0, 60.0], count: 15).flatMap { $0 }
        let result = BaselineEngine.evaluate(series: prior + [60.0])
        #expect(abs((result?.zScore ?? 0) - 1.0) < 1e-6)
    }

    @Test("a flat history cannot divide by zero")
    func zeroVarianceIsSafe() {
        let result = BaselineEngine.evaluate(series: Array(repeating: 50.0, count: 30) + [80.0])
        #expect(result != nil)
        #expect((result?.zScore ?? .nan).isFinite)
        #expect(abs(result?.zScore ?? 9) < 1e-9)
    }

    @Test("only the most recent 60 prior days form the baseline")
    func windowIsSixtyDays() {
        // 100 ancient days at 10, then 60 recent days at 50, then today at 50.
        let series = Array(repeating: 10.0, count: 100)
            + Array(repeating: 50.0, count: 60)
            + [50.0]
        let result = BaselineEngine.evaluate(series: series)
        #expect(abs((result?.mean ?? 0) - 50.0) < 1e-9,
                "ancient history leaked into the baseline")
        #expect(result?.sampleCount == 60)
    }

    @Test("a short history still produces a baseline, reporting how little it had")
    func shortHistoryStillWorks() {
        let result = BaselineEngine.evaluate(series: [48, 52, 50, 50])
        #expect(result != nil)
        #expect(result?.sampleCount == 3)
    }

    @Test("a series with no prior days has nothing to compare against")
    func noPriorDaysReturnsNil() {
        #expect(BaselineEngine.evaluate(series: [50.0]) == nil)
        #expect(BaselineEngine.evaluate(series: []) == nil)
    }

    @Test("one bad night moves today's score more than it moves the trend")
    func singleSpikeMovesTodayNotTrend() {
        let prior = Array(repeating: [40.0, 60.0], count: 20).flatMap { $0 }
        let result = BaselineEngine.evaluate(series: prior + [20.0])
        let today = abs(result?.zScore ?? 0)
        let trend = abs(result?.trendZScore ?? 0)
        #expect(today > trend,
                "a lone outlier should not drag the multi-day trend with it")
    }

    @Test("a sustained decline shows up in the trend, not just today")
    func sustainedDeclineMovesTrend() {
        let prior = Array(repeating: [40.0, 60.0], count: 20).flatMap { $0 }
        let result = BaselineEngine.evaluate(series: prior + Array(repeating: 25.0, count: 7))
        #expect((result?.trendZScore ?? 0) < -1.0,
                "seven straight poor days should read as a trend")
    }

    @Test("the reading it builds carries value, baseline and sample count together")
    func buildsAReading() {
        let prior = Array(repeating: [40.0, 60.0], count: 15).flatMap { $0 }
        let reading = BaselineEngine.reading(kind: .hrv, series: prior + [60.0])
        #expect(reading?.kind == .hrv)
        #expect(reading?.value == 60.0)
        #expect(abs((reading?.baseline ?? 0) - 50.0) < 1e-9)
        #expect(reading?.sampleCount == 30)
    }
}
