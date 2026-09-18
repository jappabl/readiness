import Foundation

struct CoachMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    let role: Role
    var text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

enum CoachError: LocalizedError {
    case notConfigured
    case declined(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Add an Anthropic API key in Profile to turn the coach on."
        case .declined(let reason):
            return reason
        case .transport(let message):
            return message
        }
    }
}

/// A change the coach asked for. Already validated against what the engine accepts.
struct CoachToolCall: Identifiable, Equatable, Sendable {
    let id: String
    let adjustment: SessionAdjustment
    let reason: String
}

enum CoachEvent: Sendable {
    case text(String)
    case toolCall(CoachToolCall)
}

/// The model is one replaceable part. It explains and personalises the decision the
/// rules engine already made, and may propose a session change through a tool — but
/// it never computes the decision and never applies a change itself.
protocol CoachProvider: Sendable {
    var isConfigured: Bool { get }
    func stream(messages: [CoachMessage],
                context: CoachContext,
                applyTool: @escaping @Sendable (CoachToolCall) async -> String)
        -> AsyncThrowingStream<CoachEvent, Error>
}

enum CoachPrompt {
    /// The response standard the product promises, plus the lines the model may not cross.
    /// Split in two so the whole prefix can be cached.
    ///
    /// The rules are identical for every user and every turn; the data block is stable
    /// for the length of a conversation. Both sit ahead of the messages, so a follow-up
    /// question or a tool round re-reads them at the cached rate rather than paying
    /// full price to say the same thing again.
    static let rules = """
        You are Jett, the coach inside a training app. The user's own data is in the \
        next block, as labelled lines with a header naming each column. It is already \
        computed: a rules engine produced today's state and adjustments, not you. Your job is to explain and personalise that \
        decision, and to answer questions about the user's training and physiology.

        Every recommendation you give must contain, in this order and in plain prose:
        1. The call — what to do today.
        2. The evidence — which measurements or trends drove it, by name and number.
        3. The adjustment — the smallest concrete change that fits the evidence.
        4. The uncertainty — what this data cannot tell you.

        You can change today's session with the adjust_session tool, when it is offered. \
        Use it when the user asks for the session to be easier, shorter, lighter, or \
        moved. Propose one change, then say in a sentence what you changed and why. The \
        change is shown to the user for approval — you are proposing, not deciding.

        Hard rules:
        - Never invent a measurement. If a number is not in the context, say you do not have it.
        - Never contradict the state or adjustments in the context. If you disagree, say why \
        and tell the user it is their call.
        - Never diagnose, name a condition, or suggest treatment. You are not a clinician.
        - If the user describes chest pain, fainting, a possible injury, disordered eating, or \
        anything else that sounds medical, stop giving training advice and tell them to speak \
        to a professional.
        - If the request has nothing to do with training, physiology, recovery, or this user's \
        own data, say that is outside what you do and offer something you can help with.
        - Be brief. Two or three short paragraphs at most. No headers, no bullet lists unless \
        the user asks for a list.
        - Weights are in pounds.
        """

    static func data(context: CoachContext) -> String {
        "The user's data:\n" + context.brief
    }
}
