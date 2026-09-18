import Testing
import Foundation
@testable import ReadinessCore

/// The first line has to carry the answer on its own, because it is the only part most
/// people read. Splitting it out is what lets it be styled as the headline it is.
@Suite("Splitting an answer into its lead")
struct CoachAnswerTests {

    @Test("the first sentence is the lead, the rest is detail")
    func firstSentenceLeads() {
        let split = CoachAnswer.split("HRV is well down. Take 15% off the bar today.")
        #expect(split.lead == "HRV is well down.")
        #expect(split.body == "Take 15% off the bar today.")
    }

    @Test("a decimal point is not the end of a sentence")
    func decimalsDoNotSplit() {
        let split = CoachAnswer.split("HRV is 14.2 ms against 53.4. That is the lowest in weeks.")
        #expect(split.lead == "HRV is 14.2 ms against 53.4.")
        #expect(split.body == "That is the lowest in weeks.")
    }

    @Test("mid-stream, before any sentence has ended, everything is still the lead")
    func partialStreamIsAllLead() {
        let split = CoachAnswer.split("HRV is well do")
        #expect(split.lead == "HRV is well do")
        #expect(split.body.isEmpty)
    }

    @Test("a line break ends the lead as surely as a full stop")
    func newlineEndsTheLead() {
        let split = CoachAnswer.split("You're under baseline.\n\nHRV drove it.")
        #expect(split.lead == "You're under baseline.")
        #expect(split.body == "HRV drove it.")
    }

    @Test("a question or an exclamation ends it too")
    func otherTerminators() {
        #expect(CoachAnswer.split("Why? Because HRV fell.").lead == "Why?")
        #expect(CoachAnswer.split("Big week! Ease off.").lead == "Big week!")
    }

    @Test("a long opening sentence is still the lead, not silently truncated")
    func longLeadIsNotCut() {
        let long = String(repeating: "word ", count: 40) + "end."
        #expect(CoachAnswer.split(long).lead.hasSuffix("end."))
    }

    @Test("empty text splits into nothing rather than crashing")
    func emptyIsSafe() {
        let split = CoachAnswer.split("")
        #expect(split.lead.isEmpty)
        #expect(split.body.isEmpty)
    }

    @Test("leading whitespace from a stream never shifts the lead")
    func whitespaceIsTrimmed() {
        #expect(CoachAnswer.split("  \n HRV is down. More.").lead == "HRV is down.")
    }
}
