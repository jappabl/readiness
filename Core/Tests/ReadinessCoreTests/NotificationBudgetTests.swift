import Testing
import Foundation
@testable import ReadinessCore

/// Jett has three coins and earns one every two days. An eventful day can spend two or
/// three; doing that leaves him quiet for a while. A weekly counter was rejected because
/// it cannot tell four-across-a-week from four-on-Monday.
@Suite("The speaking budget")
struct NotificationBudgetTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a fresh bucket allows a whole day's burst")
    func burstIsAllowed() {
        var state = NotificationBudget.State()
        for i in 0..<NotificationBudget.capacity {
            let result = NotificationBudget.consume(state, now: start)
            #expect(result.allowed, "refused message \(i + 1) of a fresh burst")
            state = result.state
        }
    }

    @Test("one more in the same instant is refused")
    func burstThenRefusal() {
        var state = NotificationBudget.State()
        for _ in 0..<NotificationBudget.capacity {
            state = NotificationBudget.consume(state, now: start).state
        }
        #expect(!NotificationBudget.consume(state, now: start).allowed)
    }

    @Test("two days of waiting earns exactly one back")
    func refill() {
        var state = NotificationBudget.State()
        for _ in 0..<NotificationBudget.capacity {
            state = NotificationBudget.consume(state, now: start).state
        }
        let later = start.addingTimeInterval(NotificationBudget.refillInterval)
        let first = NotificationBudget.consume(state, now: later)
        #expect(first.allowed)
        #expect(!NotificationBudget.consume(first.state, now: later).allowed)
    }

    @Test("a quiet fortnight does not bank more than the bucket holds")
    func doesNotOverfill() {
        var state = NotificationBudget.State()
        state = NotificationBudget.consume(state, now: start).state
        let fortnight = start.addingTimeInterval(14 * 24 * 3600)
        for i in 0..<NotificationBudget.capacity {
            let result = NotificationBudget.consume(state, now: fortnight)
            #expect(result.allowed, "refused message \(i + 1) after a quiet fortnight")
            state = result.state
        }
        #expect(!NotificationBudget.consume(state, now: fortnight).allowed)
    }

    @Test("winding the clock back does not refill the bucket")
    func clockGoingBackwardsEarnsNothing() {
        var state = NotificationBudget.State()
        for _ in 0..<NotificationBudget.capacity {
            state = NotificationBudget.consume(state, now: start).state
        }
        let yesterday = start.addingTimeInterval(-100 * 24 * 3600)
        #expect(!NotificationBudget.consume(state, now: yesterday).allowed)
    }
}
