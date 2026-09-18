import Testing
@testable import ReadinessCore

/// The gate is on the coach because the coach is the part that costs money every time
/// somebody uses it. Everything the app measures stays free: charging for a number the
/// watch already recorded is charging for someone else's work.
@Suite("Who gets the coach")
struct PaywallTests {

    @Test("a subscriber is never counted or stopped")
    func subscriberIsUnlimited() {
        for used in [0, 5, 500] {
            let allowance = Paywall.allowance(used: used, isSubscribed: true)
            #expect(allowance.isAllowed)
            #expect(allowance.remaining == nil, "a subscriber should not see a countdown")
        }
    }

    @Test("a new user gets a real try, not a teaser")
    func freeTrialIsUsable() {
        let allowance = Paywall.allowance(used: 0, isSubscribed: false)
        #expect(allowance.isAllowed)
        #expect(allowance.remaining == Paywall.freeMessages)
        #expect(Paywall.freeMessages >= 3, "fewer than three answers is not a trial")
    }

    @Test("the count runs down and then stops")
    func countdownThenWall() {
        for used in 0..<Paywall.freeMessages {
            let allowance = Paywall.allowance(used: used, isSubscribed: false)
            #expect(allowance.isAllowed, "blocked at \(used) of \(Paywall.freeMessages)")
            #expect(allowance.remaining == Paywall.freeMessages - used)
        }
        let exhausted = Paywall.allowance(used: Paywall.freeMessages, isSubscribed: false)
        #expect(!exhausted.isAllowed)
        #expect(exhausted.remaining == 0)
    }

    @Test("having gone over the limit is not worse than reaching it")
    func overshootIsClamped() {
        let allowance = Paywall.allowance(used: Paywall.freeMessages + 40, isSubscribed: false)
        #expect(!allowance.isAllowed)
        #expect(allowance.remaining == 0, "a negative count would render as nonsense")
    }

    @Test("subscribing mid-way lifts the wall immediately")
    func subscribingUnblocks() {
        let used = Paywall.freeMessages + 3
        #expect(!Paywall.allowance(used: used, isSubscribed: false).isAllowed)
        #expect(Paywall.allowance(used: used, isSubscribed: true).isAllowed)
    }

    @Test("the countdown only shows when it is nearly over")
    func countdownIsQuietUntilItMatters() {
        // Nagging from message one is how a trial teaches people to resent the app.
        #expect(!Paywall.allowance(used: 0, isSubscribed: false).showsRemaining)
        #expect(Paywall.allowance(used: Paywall.freeMessages - 1, isSubscribed: false).showsRemaining)
    }
}
