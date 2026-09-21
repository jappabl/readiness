import Testing
import Foundation
@testable import ReadinessCore

/// The engine is a pure function, so everything it remembers has to be handed to it.
@Suite("What Jett remembers saying")
struct NotificationRecordTests {

    /// Pinned to UTC. These tests assert what falls on the same day, and an unpinned
    /// calendar makes the answer depend on where the machine running them is.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let morning = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a fresh record has said nothing and has a full bucket")
    func freshRecord() {
        let record = NotificationRecord()
        #expect(record.lastMorningVerdict == nil)
        #expect(record.lastInsight == nil)
        #expect(!record.alreadySentToday(.morningVerdict, now: morning, calendar: calendar))
        #expect(NotificationBudget.consume(record.budget, now: morning).allowed)
    }

    @Test("a verdict sent this morning blocks another this afternoon")
    func sameDayIsBlocked() {
        var record = NotificationRecord()
        record.lastMorningVerdict = morning
        let afternoon = morning.addingTimeInterval(8 * 3600)
        #expect(record.alreadySentToday(.morningVerdict, now: afternoon, calendar: calendar))
    }

    @Test("a verdict sent yesterday does not block today's")
    func yesterdayDoesNotBlock() {
        var record = NotificationRecord()
        record.lastMorningVerdict = morning
        let tomorrow = morning.addingTimeInterval(24 * 3600)
        #expect(!record.alreadySentToday(.morningVerdict, now: tomorrow, calendar: calendar))
    }

    @Test("each moment is tracked separately")
    func momentsAreIndependent() {
        var record = NotificationRecord()
        record.lastMorningVerdict = morning
        #expect(record.alreadySentToday(.morningVerdict, now: morning, calendar: calendar))
        #expect(!record.alreadySentToday(.illnessGate, now: morning, calendar: calendar))
        #expect(!record.alreadySentToday(.bedtimeTarget, now: morning, calendar: calendar))
    }

    @Test("an insight is remembered by its words, not its day")
    func insightIsTextual() {
        var record = NotificationRecord()
        record.lastInsight = "Your training volume has been about 18% higher."
        // Every other moment was also said at this exact instant. If the switch ever
        // read one of those fields instead of returning early for `.newInsight`, it
        // would see a same-day match here and wrongly block — so novelty must ignore
        // the calendar regardless of what the rest of the record holds.
        record.lastMorningVerdict = morning
        record.lastIllnessGate = morning
        record.lastBedtimeTarget = morning
        #expect(!record.alreadySentToday(.newInsight, now: morning, calendar: calendar))
    }

    @Test("it survives a round trip through JSON")
    func codable() throws {
        var record = NotificationRecord()
        record.lastMorningVerdict = morning
        record.lastIllnessGate = morning.addingTimeInterval(3600)
        record.lastBedtimeTarget = morning.addingTimeInterval(7200)
        record.lastInsight = "something"
        record.budget = NotificationBudget.State(tokens: 1.5, updated: morning.addingTimeInterval(10_800))
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(NotificationRecord.self, from: data) == record)
    }
}
