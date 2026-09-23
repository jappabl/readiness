import Testing
@testable import ReadinessCore

/// What lands on Hao's phone when somebody taps Text Hao: their words first, then the
/// details he would otherwise have to ask for, and nothing about their health.
@Suite("Texting Hao")
struct FeedbackMessageTests {

    private let context = FeedbackMessage.Context(
        appVersion: "1.0.1", build: "6", systemVersion: "26.0", deviceModel: "iPhone17,2",
        screen: "Log a meal", problem: "Couldn't estimate this photo right now. Try again or enter your meal.")

    @Test("it goes to Hao's number")
    func recipient() {
        #expect(FeedbackMessage.recipient == "+14242186248")
    }

    @Test("their words go first, with room to type")
    func roomToType() {
        let body = FeedbackMessage.body(context)
        #expect(body.hasPrefix("\n\n"))
    }

    @Test("it carries the version, the phone, the screen and what went wrong")
    func carriesTheDetails() {
        let body = FeedbackMessage.body(context)
        for piece in ["1.0.1 (6)", "iPhone17,2", "iOS 26.0", "Log a meal", "Couldn't estimate this photo"] {
            #expect(body.contains(piece), "\(piece)")
        }
    }

    @Test("with nothing wrong and no screen, it is just the version and the phone")
    func plain() {
        let body = FeedbackMessage.body(.init(appVersion: "1.0.1", build: "6", systemVersion: "26.0",
                                              deviceModel: "iPhone17,2", screen: nil, problem: nil))
        #expect(body.contains("1.0.1 (6)"))
        #expect(!body.contains("Screen:"))
        #expect(!body.contains("Saw:"))
    }

    // A text message is read on a lock screen and a watch. A runaway error string should
    // not push the person's own words off the top.
    @Test("a long error is cut short")
    func longProblem() {
        let long = String(repeating: "x", count: 900)
        let body = FeedbackMessage.body(.init(appVersion: "1", build: "1", systemVersion: "26.0",
                                              deviceModel: "iPhone", screen: nil, problem: long))
        #expect(body.count < 400)
    }

    @Test("no em dashes")
    func noEmDash() {
        #expect(!FeedbackMessage.body(context).contains("\u{2014}"))
    }
}
