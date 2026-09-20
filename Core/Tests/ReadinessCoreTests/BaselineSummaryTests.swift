import Foundation
import Testing
@testable import ReadinessCore

/// The reveal claims "that's your normal now". A raw series does not show a normal, so
/// the picture needs the middle and the spread as actual numbers, derived from the
/// user's own readings rather than drawn to look plausible.
@Suite("Summarising a baseline")
struct BaselineSummaryTests {

    @Test("the middle and the spread come from the values themselves")
    func meanAndDeviation() throws {
        let summary = try #require(BaselineSummary.of([10, 12, 14, 16, 18, 20, 22]))
        #expect(abs(summary.mean - 16) < 0.001)
        #expect(summary.deviation > 3 && summary.deviation < 5)
        #expect(summary.count == 7)
    }

    @Test("the band is the middle plus and minus the spread")
    func band() throws {
        let summary = try #require(BaselineSummary.of([10, 12, 14, 16, 18, 20, 22]))
        #expect(abs(summary.low - (summary.mean - summary.deviation)) < 0.0001)
        #expect(abs(summary.high - (summary.mean + summary.deviation)) < 0.0001)
        #expect(summary.contains(16))
        #expect(!summary.contains(100))
    }

    @Test("too little history is no baseline at all, rather than a confident wrong one")
    func needsEnoughHistory() {
        #expect(BaselineSummary.of([]) == nil)
        #expect(BaselineSummary.of([50]) == nil)
        #expect(BaselineSummary.of([50, 51, 52, 53, 54, 55]) == nil)
        #expect(BaselineSummary.of([50, 51, 52, 53, 54, 55, 56]) != nil)
    }

    @Test("a flat history has no spread and still describes itself")
    func flatHistory() throws {
        let summary = try #require(BaselineSummary.of(Array(repeating: 55.0, count: 30)))
        #expect(summary.mean == 55)
        // A zero-width band would contain only one exact value, which is useless to
        // draw and misleading to read, so a flat history gets a floor rather than zero.
        #expect(summary.deviation > 0)
        #expect(summary.high > summary.low)
        #expect(summary.contains(55))
    }

    @Test("infinities and NaN cannot enter the baseline")
    func rejectsGarbage() throws {
        let summary = try #require(
            BaselineSummary.of([50, 52, .nan, 54, .infinity, 56, 58, 60, 62, 64]))
        #expect(summary.count == 8)
        #expect(summary.mean.isFinite)
        #expect(summary.deviation.isFinite)
    }

    @Test("most of a person's nights sit inside their own band")
    func mostNightsAreNormal() throws {
        // A spread of readings around 55, which is what HRV history looks like.
        let nights = (0..<60).map { 55 + sin(Double($0)) * 6 + Double($0 % 5) }
        let summary = try #require(BaselineSummary.of(nights))
        let inside = nights.filter(summary.contains).count
        #expect(Double(inside) / Double(nights.count) > 0.55)
        #expect(Double(inside) / Double(nights.count) < 0.95)
    }
}
