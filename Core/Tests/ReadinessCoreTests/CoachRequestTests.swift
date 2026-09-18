import Testing
import Foundation
@testable import ReadinessCore

/// The request shape is where the bill is decided. These pin the two properties that
/// keep it small and are easy to break by accident.
@Suite("The shape of a coach request")
struct CoachRequestTests {

    private let rules = "RULES"
    private let data = "DATA"

    private func body(offersTools: Bool = true,
                      messages: [[String: Any]] = [["role": "user", "content": "hi"]])
        -> [String: Any] {
        CoachRequest.body(model: "m", rules: rules, data: data,
                          messages: messages, offersTools: offersTools)
    }

    private func system(_ body: [String: Any]) -> [[String: Any]] {
        body["system"] as? [[String: Any]] ?? []
    }

    @Test("the cached prefix ends after the data, so the whole of it is reused")
    func cacheBreakpointIsOnTheLastSystemBlock() {
        let blocks = system(body())
        #expect(blocks.count == 2)
        #expect(blocks.first?["cache_control"] == nil,
                "a breakpoint here would split the prefix and cache too little to matter")
        #expect(blocks.last?["cache_control"] as? [String: String] == ["type": "ephemeral"],
                "without this every turn pays full price for the same 1,400 tokens")
    }

    @Test("the rules block is identical whatever the user's data says")
    func rulesAreStableAcrossContexts() {
        let one = CoachRequest.body(model: "m", rules: rules, data: "{\"a\":1}",
                                    messages: [], offersTools: true)
        let two = CoachRequest.body(model: "m", rules: rules, data: "{\"a\":2}",
                                    messages: [], offersTools: true)
        #expect(system(one).first?["text"] as? String == system(two).first?["text"] as? String)
    }

    @Test("the data block carries the context and nothing else")
    func dataBlockCarriesTheContext() {
        #expect(system(body()).last?["text"] as? String == data)
    }

    @Test("the final round is asked without tools, so it has to answer in prose")
    func finalRoundDropsTools() {
        #expect(body(offersTools: true)["tools"] != nil)
        #expect(body(offersTools: false)["tools"] == nil,
                "a tool on the last round leaves the user holding a proposal and no reply")
    }

    @Test("streaming is on, because a long answer otherwise risks the request timeout")
    func streams() {
        #expect(body()["stream"] as? Bool == true)
    }

    @Test("history is passed through untouched")
    func messagesPassThrough() {
        let sent = [["role": "user", "content": "a"], ["role": "assistant", "content": "b"]]
        let carried = body(messages: sent)["messages"] as? [[String: Any]]
        #expect(carried?.count == 2)
        #expect(carried?.last?["content"] as? String == "b")
    }
}

/// Trimming is where a cheap optimisation turns into a 400. The Messages API requires
/// the first message to be the user's, and a naive "keep the last N" can cut a
/// conversation so it opens on the assistant.
@Suite("Trimming conversation history")
struct CoachHistoryTests {

    private func turns(_ roles: [String]) -> [[String: Any]] {
        roles.enumerated().map { ["role": $0.element, "content": "m\($0.offset)"] }
    }

    @Test("a short conversation is left alone")
    func shortIsUntouched() {
        let history = turns(["user", "assistant", "user"])
        #expect(CoachRequest.trim(history, to: 16).count == 3)
    }

    @Test("only the most recent turns survive")
    func keepsTheTail() {
        let history = turns((0..<20).map { $0.isMultiple(of: 2) ? "user" : "assistant" })
        let kept = CoachRequest.trim(history, to: 6)
        #expect(kept.count <= 6)
        #expect(kept.last?["content"] as? String == "m19")
    }

    @Test("the result never opens on the assistant")
    func alwaysStartsWithTheUser() {
        // A cut landing here would leave "assistant" first, which the API rejects.
        let history = turns(["user", "assistant", "user", "assistant", "user", "assistant"])
        for limit in 1...6 {
            let kept = CoachRequest.trim(history, to: limit)
            if let first = kept.first {
                #expect(first["role"] as? String == "user",
                        "trimming to \(limit) opened on the assistant")
            }
        }
    }

    @Test("a conversation of nothing but assistant turns yields nothing to send")
    func degenerateHistory() {
        #expect(CoachRequest.trim(turns(["assistant", "assistant"]), to: 4).isEmpty)
    }
}
