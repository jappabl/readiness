import Foundation

struct CoachMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    let role: Role
    var text: String
    var reaction: CoachReaction?

    init(id: UUID = UUID(), role: Role, text: String, reaction: CoachReaction? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.reaction = reaction
    }
}

enum CoachError: LocalizedError {
    case notConfigured
    case sharingNotAllowed
    case declined(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .sharingNotAllowed:
            return "Allow sharing to chat with Jett. You can change this in Profile."
        case .notConfigured:
            return "Add a DeepSeek API key in Profile to turn the coach on."
        case .declined(let reason):
            return reason
        case .transport(let message):
            return message
        }
    }
}

/// Something the coach asked for. Already validated against what the app accepts.
///
/// The three are deliberately not equal. A session change is a proposal the user taps to
/// accept; a memory write happens immediately, because asking permission to remember a
/// sentence somebody just said would be worse than the thing it protects against. The
/// protection there is that the list is visible and deletable instead.
struct CoachToolCall: Identifiable, Equatable, Sendable {
    enum Intent: Equatable, Sendable {
        case adjust(SessionAdjustment)
        case remember(String)
        case forget(String)
    }

    let id: String
    /// The provider's own tool name, replayed verbatim when the turn continues.
    let name: String
    let intent: Intent
    let reason: String

    var adjustment: SessionAdjustment? {
        if case let .adjust(adjustment) = intent { return adjustment }
        return nil
    }
}

enum CoachEvent: Sendable {
    case text(String)
    case toolCall(CoachToolCall)
}

/// The model is one replaceable part. It explains and personalises the decision the
/// rules engine already made, and may propose a session change through a tool. But
/// it never computes the decision and never applies a change itself.
protocol CoachProvider: Sendable {
    var isConfigured: Bool { get }
    func stream(messages: [CoachMessage],
                context: CoachContext,
                applyTool: @escaping @Sendable (CoachToolCall) async -> String)
        -> AsyncThrowingStream<CoachEvent, Error>
}

/// The rules Jett answers by live on the server, in `server/src/prompt.ts`, and only
/// there.
///
/// There were two copies, a Swift one here and a TypeScript one there, kept identical by
/// hand. Through the proxy only the server's is ever sent, so this one shaped nothing
/// that shipped while still having to be edited in step: three changes in a single day
/// were made twice. The first time one of them is made once, the app behaves differently
/// in development from the way it behaves for everybody, which is worse than having no
/// local path at all.
///
/// The data block went with it for the same reason. The client sends `context.brief` and
/// the server wraps it, so the wrapping belongs there too.


/// Versioned consent is checked again at the network boundary, not just in the UI.
/// An in-flight request cannot be recalled; revocation prevents subsequent requests.
enum CoachSharing {
    /// Versioned, and bumped whenever the disclosure changes in a way that consent
    /// given to the old wording would not cover. Naming a single provider became wrong
    /// once the server could route to a different one without an app release, so who
    /// receives the data changed, and nobody's previous yes covers that.
    static let key = "coach.sharing.v3"
    static var isAllowed: Bool { UserDefaults.standard.bool(forKey: key) }
    static func setAllowed(_ allowed: Bool) { UserDefaults.standard.set(allowed, forKey: key) }
}
