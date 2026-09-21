import Foundation
import Testing
@testable import ReadinessCore

/// What Jett is allowed to carry between conversations.
///
/// Everything the app can recompute: scores, load, sleep, the programme, what was said
/// in onboarding: is rebuilt fresh in the context block every message, so remembering
/// any of it would only create a second copy that goes stale. Memory is for what nobody
/// else records: a niggle mentioned in passing, a constraint with an end date, a thing
/// they asked not to be brought up.
@Suite("What Jett remembers")
struct CoachMemoryTests {

    private let day = Date(timeIntervalSince1970: 1_700_000_000)

    private func aged(_ days: Int) -> Date { day.addingTimeInterval(Double(days) * -86_400) }

    @Test("a note is kept, and reads back with what it was told")
    func remembersOne() throws {
        var memory = CoachMemory()
        let written = memory.remember("Left shoulder clicks on overhead press", on: day)
        let note = try #require(written)
        #expect(note.text == "Left shoulder clicks on overhead press")
        #expect(memory.notes.count == 1)
    }

    @Test("nothing is a note")
    func refusesEmpty() {
        var memory = CoachMemory()
        let blank = memory.remember("   ", on: day)
        let empty = memory.remember("", on: day)
        #expect(blank == nil)
        #expect(empty == nil)
        #expect(memory.notes.isEmpty)
    }

    @Test("a note cannot be an essay")
    func trimsLongNotes() throws {
        var memory = CoachMemory()
        let written = memory.remember(String(repeating: "a", count: 400), on: day)
        let note = try #require(written)
        #expect(note.text.count == CoachMemory.maximumNoteLength)
    }

    @Test("the same fact said twice is one note, not two")
    func exactRepeatReplaces() {
        var memory = CoachMemory()
        _ = memory.remember("Trains Tuesday and Thursday only", on: aged(30))
        _ = memory.remember("trains tuesday and thursday only.", on: day)
        #expect(memory.notes.count == 1)
        #expect(memory.notes.first?.written == day, "the fact was re-confirmed today")
    }

    @Test("the same fact in different words is still one note")
    func rephrasedFactReplaces() {
        // The failure this prevents: Jett writes the shoulder down every time it comes
        // up, and six conversations later the list is the same fact six times.
        var memory = CoachMemory()
        _ = memory.remember("Left shoulder clicks on overhead press", on: aged(30))
        _ = memory.remember("Left shoulder clicks when pressing overhead", on: day)
        #expect(memory.notes.count == 1)
        #expect(memory.notes.first?.text == "Left shoulder clicks when pressing overhead",
                "the newer wording wins")
    }

    @Test("two different facts are two notes")
    func differentFactsBothKept() {
        var memory = CoachMemory()
        _ = memory.remember("Left shoulder clicks on overhead press", on: day)
        _ = memory.remember("Exams until the fifteenth", on: day)
        #expect(memory.notes.count == 2)
    }

    @Test("the list cannot grow without end")
    func evictsOldestAtCapacity() throws {
        var memory = CoachMemory()
        for index in 0..<(CoachMemory.capacity + 5) {
            _ = memory.remember("fact number \(index)", on: aged(100 - index))
        }
        #expect(memory.notes.count == CoachMemory.capacity)
        #expect(!memory.notes.contains { $0.text == "fact number 0" }, "the oldest went first")
        #expect(memory.notes.contains { $0.text == "fact number \(CoachMemory.capacity + 4)" })
    }

    @Test("forgetting removes exactly one note")
    func forgets() throws {
        var memory = CoachMemory()
        let written = memory.remember("Hates running", on: day)
        let first = try #require(written)
        _ = memory.remember("Exams until the fifteenth", on: day)
        let removed = memory.forget(id: first.id)
        #expect(removed)
        #expect(memory.notes.count == 1)
        let removedAgain = memory.forget(id: first.id)
        #expect(!removedAgain, "already gone")
    }

    @Test("a note can be dropped by naming it, not by knowing an id")
    func forgetsByWording() throws {
        var memory = CoachMemory()
        _ = memory.remember("Exams until the fifteenth of March", on: day)
        _ = memory.remember("Hates running", on: day)
        let dropped = memory.forget(matching: "exams until the fifteenth")
        #expect(dropped?.text == "Exams until the fifteenth of March")
        #expect(memory.notes.count == 1)
        let missing = memory.forget(matching: "something never said")
        #expect(missing == nil)
    }

    @Test("an empty memory adds nothing to the prompt")
    func emptyRendersNothing() {
        #expect(CoachMemory().brief(asOf: day).isEmpty)
    }

    @Test("notes carry their age, so a stale one can be recognised as stale")
    func briefCarriesAge() throws {
        var memory = CoachMemory()
        _ = memory.remember("Exams until the fifteenth", on: aged(21))
        _ = memory.remember("Hates running", on: day)
        let brief = memory.brief(asOf: day)
        #expect(brief.contains("Exams until the fifteenth"))
        #expect(brief.contains("3 weeks ago"))
        #expect(brief.contains("today"))
        // Oldest first, so the freshest thing sits closest to the question.
        let exams = try #require(brief.range(of: "Exams"))
        let running = try #require(brief.range(of: "Hates running"))
        #expect(exams.lowerBound < running.lowerBound)
    }

    @Test("the block cannot crowd out the day's own numbers")
    func briefStaysInsideItsBudget() {
        var memory = CoachMemory()
        for index in 0..<CoachMemory.capacity {
            _ = memory.remember(String(repeating: "word\(index) ", count: 30), on: aged(index))
        }
        #expect(memory.brief(asOf: day).utf8.count <= CoachMemory.maximumBriefBytes)
    }

    @Test("it survives being written down and read back")
    func roundTrips() throws {
        var memory = CoachMemory()
        _ = memory.remember("Left shoulder clicks on overhead press", on: day)
        let data = try JSONEncoder().encode(memory)
        #expect(try JSONDecoder().decode(CoachMemory.self, from: data) == memory)
    }
}
