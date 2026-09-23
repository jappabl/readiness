import Foundation

/// The text that opens in Messages when somebody taps Text Hao.
///
/// The details Hao would otherwise have to ask for, on one bracketed line, then an empty
/// line. Messages puts the cursor at the end of a pre-filled body and there is no way to
/// move it, so ending on the empty line is what leaves them ready to type. They see all
/// of it before sending, and none of it is about their health: no scores, no readings,
/// nothing from the coach conversation.
public enum FeedbackMessage {

    /// A Google Voice number, so Hao's own stays private and can be retired.
    public static let recipient = "+14242186248"

    /// Long enough for any message the app shows, short enough not to bury theirs.
    static let problemLimit = 160

    public struct Context: Sendable, Equatable {
        public let appVersion: String
        public let build: String
        public let systemVersion: String
        public let deviceModel: String
        /// Where they were, in the words the screen uses.
        public let screen: String?
        /// What the app had just told them, when that is why they are texting.
        public let problem: String?

        public init(appVersion: String, build: String, systemVersion: String,
                    deviceModel: String, screen: String?, problem: String?) {
            self.appVersion = appVersion
            self.build = build
            self.systemVersion = systemVersion
            self.deviceModel = deviceModel
            self.screen = screen
            self.problem = problem
        }
    }

    public static func body(_ context: Context) -> String {
        var details = ["Coach Jett \(context.appVersion) (\(context.build))",
                       "\(context.deviceModel), iOS \(context.systemVersion)"]
        if let screen = context.screen, !screen.isEmpty { details.append("Screen: \(screen)") }
        if let problem = context.problem?.trimmingCharacters(in: .whitespacesAndNewlines),
           !problem.isEmpty {
            let cut = problem.count > problemLimit
                ? String(problem.prefix(problemLimit)) + "..." : problem
            details.append("Saw: \"\(cut)\"")
        }
        return "(" + details.joined(separator: ". ") + ")\n\n"
    }
}
