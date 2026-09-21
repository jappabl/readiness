import Testing
@testable import ReadinessCore

/// Which moments compete for an allowance and which are exempt. The morning verdict is
/// the app's core output, not one nice-to-have among several, so it never queues behind
/// an insight.
@Suite("What a notification moment costs")
struct NotificationMomentTests {

    @Test("the core output and the illness gate are free")
    func exemptMoments() {
        #expect(!NotificationMoment.morningVerdict.spendsBudget)
        #expect(!NotificationMoment.illnessGate.spendsBudget)
    }

    @Test("the extras are budgeted")
    func budgetedMoments() {
        #expect(NotificationMoment.newInsight.spendsBudget)
        #expect(NotificationMoment.bedtimeTarget.spendsBudget)
    }

    @Test("every moment has an answer, so a new case cannot be forgotten")
    func everyCaseIsClassified() {
        #expect(NotificationMoment.allCases.count == 4)
    }
}
