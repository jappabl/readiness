import Foundation
import Testing
@testable import ReadinessCore

/// The chart under the sleep-debt row, which has to be the same quantity as the number
/// above it.
///
/// It was not. The caller walked a growing prefix of the whole record and called
/// `SleepDebt.of` on each one, and `of` learns its reference from every night it is
/// handed while accumulating over only the last seven — so each point was measured
/// against a different reference, ending at the whole record's median while the row used
/// the last twenty-eight nights'. The line could sit pinned at the cap for most of its
/// length under a row reading "you are not down on sleep".
@Suite("The balance as it ran")
struct SleepDebtHistoryTests {

    private let points = 28

    /// The property that was false: the line ends where the number says it is.
    @Test("the last point is the number the row shows")
    func lastPointMatchesTheRow() throws {
        let summerThenTerm: [Double] = Array(repeating: 9.0, count: 152)
            + Array(repeating: 7.5, count: 28)
        let slippedHabit: [Double] = Array(repeating: 8.0, count: 150)
            + Array(repeating: 6.5, count: 30)
        let longSleeperSettling: [Double] = Array(repeating: 10.0, count: 60)
            + Array(repeating: 8.0, count: 40)
        let badWeek: [Double] = Array(repeating: 7.5, count: 40)
            + Array(repeating: 4.0, count: 7)
        let wobbly: [Double] = (0..<180).map { 7.0 + sin(Double($0)) }
        let cases: [[Double]] = [summerThenTerm, slippedHabit, longSleeperSettling,
                                 badWeek, wobbly]
        for nights in cases {
            let row = SleepDebt.of(nights: Array(nights.suffix(points))).hours
            let head = try #require(SleepDebt.history(nights: nights, points: points).last)
            #expect(abs(head - row) < 0.001,
                    "chart ended at \(head) under a row reading \(row)")
        }
    }

    /// The case both audits reached independently: a long stretch of long nights followed
    /// by a month of ordinary ones. The whole record's median is 9.0, the last
    /// twenty-eight nights' is 7.5, and the row says nothing is owed.
    @Test("a settled sleeper's line does not run to the cap behind their back")
    func settledSleeperReadsZero() throws {
        let nights = Array(repeating: 9.0, count: 152) + Array(repeating: 7.5, count: 28)
        let drawn = SleepDebt.history(nights: nights, points: points)
        #expect(SleepDebt.of(nights: Array(nights.suffix(points))).hours == 0)
        #expect(drawn.allSatisfy { $0 == 0 },
                "drawn \(drawn.map { ($0 * 10).rounded() / 10 })")
    }

    /// One reference for the whole line, so a rise means less sleep and never a reference
    /// that moved underneath it. Drawn across a record that changes habit halfway, every
    /// point has to be explicable by the nights alone.
    @Test("the reference does not move while the line is drawn")
    func oneReferenceThroughout() {
        let nights = Array(repeating: 6.0, count: 20) + Array(repeating: 9.5, count: 20)
        let drawn = SleepDebt.history(nights: nights, points: points)
        // The last seven nights are all 9.5 against a reference of at most 9.5, so the
        // balance is paid off by the end whatever the reference turns out to be.
        #expect(drawn.last == 0)
        // And the same list, truncated one night earlier, must draw the same shape for
        // the points they share. A moving reference is exactly what breaks this.
        let earlier = SleepDebt.history(nights: Array(nights.dropLast()), points: points)
        #expect(abs(earlier.suffix(5).first! - drawn.dropLast().suffix(5).first!) < 0.001)
    }

    /// A short record draws what it has rather than padding to the window.
    @Test("fewer nights than points draws fewer points")
    func shortRecord() {
        #expect(SleepDebt.history(nights: [7.0, 7.0, 6.0], points: points).count == 3)
        #expect(SleepDebt.history(nights: [], points: points).isEmpty)
    }

    /// And a bad week inside a good habit still climbs, because that is what the card is
    /// for.
    @Test("a bad week is visible in the line")
    func badWeekClimbs() throws {
        let nights = Array(repeating: 7.5, count: 40) + Array(repeating: 4.0, count: 7)
        let drawn = SleepDebt.history(nights: nights, points: points)
        #expect(drawn.first == 0)
        #expect(try #require(drawn.last) >= SleepDebt.maximumHours - 0.001)
        #expect(zip(drawn.suffix(7), drawn.suffix(7).dropFirst()).allSatisfy { $1 >= $0 },
                "the bad week did not climb monotonically: \(drawn.suffix(8))")
    }
}
