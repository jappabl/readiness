import Foundation

/// What the coach is allowed to do to a session.
///
/// The model proposes; this validates. Anything it sends is clamped to what the
/// prescription engine will actually accept, so a bad tool call becomes a safe
/// adjustment or nothing at all: never an out-of-range instruction.
public enum CoachTools {

    public static let adjustSession = "adjust_session"
    public static let remember = "remember"
    public static let forget = "forget"

    /// Bounds the model cannot argue with.
    public static let setReductionRange = 5...50
    public static let loadReductionRange = 5...20
    public static let effortCapRange = 0...6

    public static let defaultSetReduction = 20
    public static let defaultLoadReduction = 10
    public static let defaultEffortCap = 3

    public static func adjustment(action: String, percent: Int?, rir: Int?) -> SessionAdjustment? {
        func clamp(_ value: Int?, _ range: ClosedRange<Int>, default fallback: Int) -> Int {
            guard let value else { return fallback }
            return min(max(value, range.lowerBound), range.upperBound)
        }

        switch action {
        case "reduce_sets":
            return .reduceWorkingSets(
                percent: clamp(percent, setReductionRange, default: defaultSetReduction))
        case "reduce_load":
            return .reduceLoad(
                percent: clamp(percent, loadReductionRange, default: defaultLoadReduction))
        case "cap_effort":
            return .capEffort(rir: clamp(rir, effortCapRange, default: defaultEffortCap))
        case "defer_lower_body":
            return .deferLowerBody
        case "proceed_as_planned":
            return .proceedAsPlanned
        default:
            // An action the app cannot honour is refused. Guessing at intent is how a
            // coach ends up doing something nobody asked for.
            return nil
        }
    }

    /// Every schema handed to the model, on the direct path. The proxy keeps its own
    /// copy in `server/src/prompt.ts`; the two must not drift.
    public static var schemas: [[String: Any]] { [schema, rememberSchema, forgetSchema] }

    public static var rememberSchema: [String: Any] {
        [
            "name": remember,
            "description": "Write one short fact about this person down so it is still "
                + "there in a month. Only for what the data block does not already carry: "
                + "an injury mentioned in conversation, a constraint with an end date, a "
                + "standing preference, or a commitment you made. Never their scores, load, "
                + "sleep, programme, goal or equipment. Those arrive fresh every message. "
                + "Most messages need no call at all.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "note": [
                        "type": "string",
                        "description": "The fact in one short line, written about them "
                            + "rather than to them. For example \"Left shoulder clicks on "
                            + "overhead press\".",
                    ],
                ],
                "required": ["note"],
            ],
        ]
    }

    public static var forgetSchema: [String: Any] {
        [
            "name": forget,
            "description": "Drop a fact from the list because it is out of date or wrong. "
                + "Name it in its own words, copied from the list in the block.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "note": [
                        "type": "string",
                        "description": "The note to drop, as it appears in the list.",
                    ],
                ],
                "required": ["note"],
            ],
        ]
    }

    /// The JSON schema handed to the model.
    public static var schema: [String: Any] {
        [
            "name": adjustSession,
            "description": """
                Change today's planned lifting session. Use this when the user asks you to \
                make the session easier, harder, shorter, or to move it. Propose one change \
                at a time. The change is shown to the user for approval: it is never applied \
                silently.
                """,
            "input_schema": [
                "type": "object",
                "properties": [
                    "action": [
                        "type": "string",
                        "enum": ["reduce_sets", "reduce_load", "cap_effort",
                                 "defer_lower_body", "proceed_as_planned"],
                        "description": "Which change to make.",
                    ],
                    "percent": [
                        "type": "integer",
                        "description": "For reduce_sets or reduce_load: how much to cut, "
                            + "as a whole percent.",
                    ],
                    "rir": [
                        "type": "integer",
                        "description": "For cap_effort: reps to leave in reserve on every set.",
                    ],
                    "reason": [
                        "type": "string",
                        "description": "One short sentence naming the measurement that "
                            + "justifies this, for the user to read.",
                    ],
                ],
                "required": ["action", "reason"],
            ],
        ]
    }
}
