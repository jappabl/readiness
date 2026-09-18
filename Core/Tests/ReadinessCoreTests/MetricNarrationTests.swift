import Testing
import Foundation
@testable import ReadinessCore

/// Three lines on a screen are three lines. Each one has to say what it means, in the
/// few words somebody will actually read under a chart.
@Suite("Reading a chart in one line")
struct MetricNarrationTests {

    private func reading(_ z: Double, value: Double = 50) -> MetricReading {
        MetricReading(kind: .hrv, value: value, baseline: 50, zScore: z, sampleCount: 60)
    }

    @Test("a number sitting in its usual range says so")
    func usualIsCalledUsual() {
        let flat = Array(repeating: 50.0, count: 14)
        let line = MetricNarration.brief(reading: reading(0.2, value: 50), series: flat)
        #expect(line.localizedCaseInsensitiveContains("usual"))
    }

    @Test("today being the lowest of the window is the most useful thing to say")
    func extremesWin() {
        let series = [60.0, 58, 57, 59, 55, 54, 40]
        let line = MetricNarration.brief(reading: reading(-2.4, value: 40), series: series)
        #expect(line.localizedCaseInsensitiveContains("lowest"))
        #expect(line.contains("\(series.count)"), "say over what window")
    }

    @Test("and so is being the highest")
    func highestIsNamed() {
        let series = [40.0, 42, 41, 44, 43, 45, 62]
        let line = MetricNarration.brief(reading: reading(2.6, value: 62), series: series)
        #expect(line.localizedCaseInsensitiveContains("highest"))
    }

    @Test("a move that is not an extreme still says which way it went")
    func directionWhenNotExtreme() {
        let series = [30.0, 70, 45, 52, 48, 61, 58]
        let line = MetricNarration.brief(reading: reading(1.4, value: 58), series: series)
        #expect(line.localizedCaseInsensitiveContains("above"))
        #expect(!line.localizedCaseInsensitiveContains("highest"), "58 is not the highest here")
    }

    @Test("it stays short enough to read under a chart")
    func staysShort() {
        let series = [60.0, 58, 57, 59, 55, 54, 40]
        for z in [-3.0, -1.2, -0.1, 0.9, 2.8] {
            let line = MetricNarration.brief(reading: reading(z, value: 40), series: series)
            #expect(line.count <= 40, "\"\(line)\" is \(line.count) characters")
        }
    }

    @Test("a window too short to compare against says nothing about extremes")
    func tooLittleHistory() {
        let line = MetricNarration.brief(reading: reading(-2.4, value: 40), series: [40])
        #expect(!line.localizedCaseInsensitiveContains("lowest"))
        #expect(!line.isEmpty, "there is still a direction to report")
    }

    @Test("an empty series never crashes and never invents a claim")
    func emptySeries() {
        let line = MetricNarration.brief(reading: reading(0.4), series: [])
        #expect(!line.isEmpty)
        #expect(!line.localizedCaseInsensitiveContains("lowest"))
    }
}
