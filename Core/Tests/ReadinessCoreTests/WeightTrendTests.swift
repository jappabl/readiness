import Foundation
import Testing
@testable import ReadinessCore

/// Whether the number is moving.
///
/// A tester logged one weigh-in, saw "185.0 lb" with nothing beside it, and wrote that
/// the app gave him no way to tell whether he was losing anything. The sparkline that
/// would have told him only appears at two readings.
@Suite("Is the number moving")
struct WeightTrendTests {

    private func day(_ offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset,
                              to: Calendar.current.startOfDay(for: Date()))!
    }
    private func reading(_ offset: Int, _ kg: Double) -> WeightTrend.Reading {
        WeightTrend.Reading(date: day(offset), kilograms: kg)
    }

    @Test func oneWeighInHasNothingToCompareItWith() {
        #expect(WeightTrend.latestChange(in: []) == nil)
        #expect(WeightTrend.latestChange(in: [reading(0, 84)]) == nil)
    }

    @Test func twoWeighInsGiveADirectionAndAGap() throws {
        let change = try #require(WeightTrend.latestChange(in: [reading(-7, 84.0), reading(0, 83.2)]))
        #expect(change.isDown)
        #expect(abs(change.kilograms + 0.8) < 0.0001)
        #expect(change.days == 7)
    }

    @Test func goingUpIsReportedAsGoingUp() throws {
        let change = try #require(WeightTrend.latestChange(in: [reading(-3, 80), reading(0, 81)]))
        #expect(!change.isDown)
        #expect(abs(change.kilograms - 1) < 0.0001)
    }

    /// Two weigh-ins on one morning are one morning's answer. "Down 0.3 since today" is
    /// noise wearing the clothes of information.
    @Test func aSecondWeighInOnTheSameDayIsNotAComparison() throws {
        let morning = Calendar.current.date(byAdding: .hour, value: 7, to: day(0))!
        let evening = Calendar.current.date(byAdding: .hour, value: 21, to: day(0))!
        let sameDayOnly = [WeightTrend.Reading(date: morning, kilograms: 84.0),
                           WeightTrend.Reading(date: evening, kilograms: 84.3)]
        #expect(WeightTrend.latestChange(in: sameDayOnly) == nil)

        let withHistory = sameDayOnly + [reading(-5, 85.0)]
        let change = try #require(WeightTrend.latestChange(in: withHistory))
        #expect(change.days == 5)
        #expect(abs(change.kilograms + 0.7) < 0.0001)
    }

    @Test func orderOfEntryDoesNotMatter() throws {
        let change = try #require(WeightTrend.latestChange(in: [reading(0, 83.2), reading(-7, 84.0)]))
        #expect(change.isDown)
        #expect(change.days == 7)
    }

    // MARK: - What the chart is drawn from

    /// Three readings stacked on one morning draw a vertical line and read as a crash.
    @Test func theChartTakesOneReadingADay() {
        let morning = Calendar.current.date(byAdding: .hour, value: 7, to: day(0))!
        let evening = Calendar.current.date(byAdding: .hour, value: 21, to: day(0))!
        let daily = WeightTrend.daily([reading(-1, 85),
                                       WeightTrend.Reading(date: morning, kilograms: 84.0),
                                       WeightTrend.Reading(date: evening, kilograms: 84.4)])
        #expect(daily.count == 2)
        #expect(daily.last?.kilograms == 84.4, "the last weigh-in of a day is the one settled on")
        #expect(daily.first?.kilograms == 85)
    }

    /// Anchored to the last weigh-in rather than to today, so somebody who stopped
    /// weighing themselves a fortnight ago still sees what they recorded.
    @Test func theWindowEndsAtTheLastWeighInNotAtToday() {
        // The window runs back 28 days from the last weigh-in, at day -15, so it reaches
        // day -42. The reading at -50 falls outside it; the one at -40 does not.
        let stale = [reading(-50, 91), reading(-40, 90), reading(-20, 88), reading(-15, 87)]
        let window = WeightTrend.window(stale, days: 28)
        #expect(window.count == 3)
        #expect(window.first?.kilograms == 90)
        #expect(window.last?.kilograms == 87)
    }

    @Test func anEmptyHistoryChartsNothingRatherThanCrashing() {
        #expect(WeightTrend.window([], days: 28).isEmpty)
        #expect(WeightTrend.daily([]).isEmpty)
    }
}
