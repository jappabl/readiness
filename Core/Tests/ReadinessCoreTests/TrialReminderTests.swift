import Testing
import Foundation
@testable import ReadinessCore

@Suite("Telling somebody before they are charged")
struct TrialReminderTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("the reminder lands two days before the trial ends")
    func landsBeforeTheEnd() throws {
        let ends = now.addingTimeInterval(14 * 86_400)
        let fire = try #require(TrialReminder.fireDate(trialEnds: ends, now: now))
        #expect(fire == ends.addingTimeInterval(-TrialReminder.lead))
        #expect(fire > now)
    }

    @Test("a trial that already ended gets nothing")
    func nothingAfterTheEnd() {
        #expect(TrialReminder.fireDate(trialEnds: now.addingTimeInterval(-1), now: now) == nil)
    }

    // Somebody who subscribes with less than the lead time left would otherwise be
    // handed a notification dated in the past, which iOS delivers immediately: a
    // warning about a charge that has effectively already happened.
    @Test("a trial ending inside the lead time gets nothing")
    func nothingInsideTheLead() {
        let ends = now.addingTimeInterval(TrialReminder.lead - 60)
        #expect(TrialReminder.fireDate(trialEnds: ends, now: now) == nil)
        #expect(TrialReminder.fireDate(trialEnds: now.addingTimeInterval(TrialReminder.lead),
                                       now: now) == nil)
    }

    // The number in the sentence and the number in the schedule are the same number.
    // They drifted apart in this codebase once already, in a different file.
    @Test("the words count the same days the schedule does")
    func wordsMatchTheSchedule() {
        #expect(TrialReminder.body(priceLine: "$8.99 a month")
            .contains("\(Int(TrialReminder.lead / 86_400)) days"))
    }

    @Test("the body says the price, and how to stop it, without needing a screen")
    func standsAloneOnALockScreen() {
        let body = TrialReminder.body(priceLine: "$8.99 a month")
        #expect(body.contains("$8.99 a month"))
        #expect(body.lowercased().contains("cancel"))
        #expect(body.contains("Coach Jett"))
        #expect(!body.contains("—"))
    }
}
