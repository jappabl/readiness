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

    @Test("winding the clock back neither refills the bucket nor drains it")
    func clockGoingBackwardsNeitherRefillsNorDrains() {
        // Asserting refusal from an empty bucket cannot pin the backwards-clock clamp:
        // with the clamp, elapsed is zero and tokens stay at zero, refused; without it,
        // a hugely negative elapsed time only drives tokens further negative, still
        // refused. Either way the assertion holds, so deleting the clamp would not turn
        // this test red. A partly used bucket is where the two worlds diverge: without
        // the clamp, the same backwards jump drives tokens deeply negative and wrongly
        // refuses a message that should still be allowed.
        let state = NotificationBudget.consume(NotificationBudget.State(), now: start).state
        let yesterday = start.addingTimeInterval(-100 * 24 * 3600)
        let result = NotificationBudget.consume(state, now: yesterday)
        #expect(result.allowed)
        #expect(result.state == NotificationBudget.State(tokens: 1, updated: yesterday))
    }
}
