import Foundation
import Testing
@testable import ReadinessCore

/// "Your seven-day trend" has to mean seven days.
///
/// It meant the last seven *readings*. Every engine here takes `suffix(n)` of a list that
/// has already had its missing days compacted out, so for somebody who wears the watch
/// four nights a week the seven-day HRV trend actually spans about twelve days, and after
/// a trip it reaches back seventeen. HRV is the only metric scored on its trend and it
/// carries the heaviest weight of the five, so a dip that recovered a fortnight ago was
/// still holding the ring down: worth up to eighteen points, on physiology that had
/// already returned to normal.
@Suite("A week means a week")
struct TrendWindowTests {

    /// Ninety days of steady HRV with a dip that ended `daysAgo` days before today.
    private func history(dipEnding daysAgo: Int, dipDays: Int = 9) -> [Double] {
        (0..<90).map { day in
            let age = 89 - day
            return (age >= daysAgo && age < daysAgo + dipDays) ? 44.0 : 58.0
        }
    }

    /// Keep only the days this person actually wore the watch, as `[Double?]`.
    private func worn(_ values: [Double], everyNth: Int) -> [Double?] {
        values.enumerated().map { index, value in
            // Today is always recorded; otherwise every nth day.
            (index == values.count - 1 || index % everyNth == 0) ? value : nil
        }
    }

    /// The property: two people with identical physiology by date, one wearing the watch
    /// nightly and one wearing it four nights a week, must read about the same.
    @Test("wearing the watch less often does not change the trend",
          arguments: [2, 3, 4])
    func wearPatternDoesNotMoveTheTrend(everyNth: Int) throws {
        let values = history(dipEnding: 8)
        let dense = try #require(BaselineEngine.evaluate(daily: values.map { $0 }))
        let gappy = try #require(BaselineEngine.evaluate(daily: worn(values, everyNth: everyNth)))
        #expect(abs(dense.trendZScore - gappy.trendZScore) < 0.35,
                "every \(everyNth) days: trend z \(gappy.trendZScore) against \(dense.trendZScore)")
    }

    /// And a dip that has genuinely recovered stops mattering, on the calendar rather than
    /// on the reading count.
    /// A dip that ended yesterday still reads as one; a dip that ended a fortnight ago
    /// does not. (It reads slightly *above* baseline once it is old, which is right: the
    /// dip is still inside the sixty-day mean it is measured against, so an ordinary day
    /// now genuinely sits above that mean.)
    @Test("a recovered dip stops counting")
    func recoveredDipFades() throws {
        let recent = try #require(BaselineEngine.evaluate(daily: history(dipEnding: 1).map { $0 }))
        let old = try #require(BaselineEngine.evaluate(daily: history(dipEnding: 14).map { $0 }))
        #expect(recent.trendZScore < -0.5, "a dip that ended yesterday barely registered")
        #expect(old.trendZScore > -0.1,
                "a fortnight-old dip was still holding it down: \(old.trendZScore)")
        #expect(old.trendZScore > recent.trendZScore + 1,
                "\(old.trendZScore) against \(recent.trendZScore)")
    }

    /// Today still counts for the most, and a missing day never becomes a reading.
    /// Today counts for more than the week, and one bad day still moves the week.
    /// A little ordinary night-to-night variation, or there is no spread to score against.
    @Test("the most recent day carries the most weight")
    func recencyDominates() throws {
        var values = (0..<90).map { 58.0 + (Double($0 % 5) - 2) * 1.5 }
        values[89] = 40
        let result = try #require(BaselineEngine.evaluate(daily: values.map { $0 }))
        #expect(result.zScore < result.trendZScore, "today should read worse than the week")
        #expect(result.trendZScore < -0.3, "one bad day moved the week not at all")
    }

    /// A record with nothing in it says nothing, rather than guessing.
    @Test("no readings, no trend")
    func emptyIsNil() {
        #expect(BaselineEngine.evaluate(daily: Array(repeating: nil, count: 30)) == nil)
        #expect(BaselineEngine.evaluate(daily: []) == nil)
    }

    /// A week off, then one night back. The trend exists to stop a single night deciding
    /// the score, and renormalising over the recorded days handed that night the whole of
    /// the missing week's weight: 65% of its own "seven-day trend" after seven days off,
    /// 93% after a fortnight. One ordinary-ish night read past the composite clamp.
    @Test("one night back after a gap is not a week's trend",
          arguments: [3, 5, 7, 14, 21])
    func oneNightDoesNotBecomeTheTrend(gap: Int) throws {
        // Settled, with the ordinary night-to-night variation a real record has: a flat
        // line has no spread, so nothing can be unusual against it.
        var values: [Double?] = (0..<120).map { 55.0 + (Double($0 % 7) - 3) * 0.8 }
        values.append(contentsOf: Array(repeating: nil, count: gap))
        values.append(51.0)
        let result = try #require(BaselineEngine.evaluate(daily: values))
        // The night itself is well below baseline; the week it lands in mostly is not.
        #expect(result.zScore < -1)
        let message = "after \(gap) days off the trend was \(result.trendZScore) "
            + "against today's \(result.zScore)"
        #expect(result.trendZScore > result.zScore * 0.75, "\(message)")
    }

    /// And a fully worn record is unaffected: there is no missing weight to place.
    @Test("a complete record places no weight on the mean")
    func fullWearUnchanged() throws {
        let values: [Double?] = (0..<90).map { 55.0 + (Double($0 % 7) - 3) * 1.2 }
        let result = try #require(BaselineEngine.evaluate(daily: values))
        // Reconstruct the plain normalised decay over the same record.
        var weighted = 0.0, weights = 0.0
        for (offset, value) in values.reversed().enumerated() {
            let w = pow(BaselineEngine.trendRetention, Double(offset))
            weighted += (value ?? 0) * w
            weights += w
        }
        let plain = (weighted / weights - result.mean) / result.sd
        #expect(abs(result.trendZScore - plain) < 0.02,
                "full wear diverged: \(result.trendZScore) against \(plain)")
    }
}
