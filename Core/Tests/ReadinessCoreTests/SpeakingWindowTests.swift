import Foundation
import Testing
@testable import ReadinessCore

/// Whether Jett is allowed to speak, before anything is decided about whether he has
/// anything to say.
///
/// The clock governed both of the app's triggers, and only one of them is a guess. A
/// night that ends at four in the morning is a night whose verdict was dropped on the
/// floor, every time, for anybody who works nights.
@Suite("When Jett is allowed to speak")
struct SpeakingWindowTests {

    private func at(_ hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 30, second: 0, of: Date())!
    }

    // MARK: - Closing the app tells us nothing

    @Test("the clock governs the trigger that carries no evidence",
          arguments: [(6, true), (12, true), (22, true), (23, false), (2, false), (4, false), (5, true)])
    func quietHoursStillApplyToTheAppClosing(hour: Int, allowed: Bool) {
        #expect(SpeakingWindow.allows(.appClosed, at: at(hour)) == allowed)
    }

    // MARK: - A synced night is a record of being awake

    /// The whole point. A watch hands over a finished night because somebody woke up and
    /// it synced, so the hour it happened at is not a reason to stay silent.
    @Test("a finished night is heard at any hour", arguments: [0, 2, 4, 5, 9, 16, 23])
    func asyncedNightIsAlwaysWelcome(hour: Int) {
        #expect(SpeakingWindow.allows(.nightSynced, at: at(hour)))
    }

    // MARK: - But not instantly

    /// A watch syncs the moment a night ends, which can be minutes before anybody has
    /// their eyes open.
    @Test func awokenPhoneWaitsLongEnoughToBeSureTheyAreUp() {
        let delay = SpeakingWindow.delay(after: .nightSynced)
        #expect(delay >= 10 * 60)
        #expect(delay <= 15 * 60)
    }

    /// Closing the app is already the person acting, so there is nothing to wait for.
    @Test func closingTheAppIsNotDelayed() {
        #expect(SpeakingWindow.delay(after: .appClosed) == 0)
    }
}
