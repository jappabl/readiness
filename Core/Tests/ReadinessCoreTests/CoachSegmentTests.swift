import Testing
import Foundation
@testable import ReadinessCore

/// Charts are requested by a marker in the text rather than a tool call, because a tool
/// call costs a whole extra request — the entire prefix re-read, and a second round trip
/// before a single word appears. A marker costs about six tokens and no round trip.
///
/// The hard part is the stream: the marker arrives one character at a time, so a naive
/// parser shows the user "[cha" for a few frames before it becomes a chart.
@Suite("Reading charts out of an answer")
struct CoachSegmentTests {

    @Test("plain prose is one run of text")
    func plainText() {
        #expect(CoachSegments.parse("You're flat today.") == [.text("You're flat today.")])
    }

    @Test("a marker becomes a chart between the text around it")
    func markerSplitsText() {
        let parsed = CoachSegments.parse("Lowest in weeks.\n[chart:hrv]\nTake 15% off.")
        #expect(parsed == [.text("Lowest in weeks."), .chart(.hrv), .text("Take 15% off.")])
    }

    @Test("a marker alone is just the chart")
    func markerAlone() {
        #expect(CoachSegments.parse("[chart:restingHeartRate]") == [.chart(.restingHeartRate)])
    }

    @Test("a half-arrived marker is never shown as text")
    func partialMarkerIsHidden() {
        // Exactly what the user would see mid-stream, one character at a time.
        for partial in ["[", "[c", "[cha", "[chart", "[chart:", "[chart:hr"] {
            let parsed = CoachSegments.parse("You're flat. " + partial)
            #expect(parsed == [.text("You're flat.")], "leaked \(partial) to the screen")
        }
    }

    @Test("a metric we cannot draw leaves no debris on screen")
    func unknownMetricIsDropped() {
        #expect(CoachSegments.parse("Before [chart:banana] after")
                == [.text("Before"), .text("after")])
    }

    @Test("two charts both survive")
    func twoCharts() {
        let parsed = CoachSegments.parse("[chart:hrv] and [chart:sleepDebt]")
        #expect(parsed == [.chart(.hrv), .text("and"), .chart(.sleepDebt)])
    }

    @Test("an opening bracket that is not a marker is left alone")
    func unrelatedBracketSurvives() {
        #expect(CoachSegments.parse("Sets [3x5] today") == [.text("Sets [3x5] today")])
    }

    @Test("empty text parses to nothing")
    func emptyIsEmpty() {
        #expect(CoachSegments.parse("").isEmpty)
    }

    @Test("every metric the context carries can be asked for by name")
    func allMetricsAreReachable() {
        for kind in MetricKind.allCases {
            #expect(CoachSegments.parse("[chart:\(kind.rawValue)]") == [.chart(kind)],
                    "\(kind.rawValue) could not be drawn")
        }
    }
}
