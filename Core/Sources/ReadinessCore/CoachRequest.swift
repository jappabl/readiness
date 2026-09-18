import Foundation

/// Builds the Messages API request body.
///
/// Pulled out of the networking so the two decisions that set the bill can be tested:
/// where the cache breakpoint sits, and whether the last round is allowed a tool.
public enum CoachRequest {

    /// Answers are meant to be under sixty words. This is a ceiling, not a target, but
    /// leaving it at four figures invites the wall of text the voice rules exist to
    /// prevent — and output tokens are the expensive half of the bill.
    public static let maximumOutputTokens = 400

    /// The most recent `limit` turns, starting on a user message.
    ///
    /// Old turns are paid for on every request and add almost nothing — the data block
    /// already carries the state of the world. But the API requires the first message
    /// to be the user's, so a plain tail can produce a request that is rejected
    /// outright rather than merely expensive.
    public static func trim(_ messages: [[String: Any]], to limit: Int) -> [[String: Any]] {
        var kept = Array(messages.suffix(max(0, limit)))
        while let first = kept.first, (first["role"] as? String) != "user" {
            kept.removeFirst()
        }
        return kept
    }

    public static func body(model: String,
                            rules: String,
                            data: String,
                            messages: [[String: Any]],
                            offersTools: Bool,
                            maxTokens: Int = maximumOutputTokens) -> [String: Any] {
        // One breakpoint, after the data. The rules and the tool schema together are too
        // short to be worth caching on their own, and the data does not change inside a
        // conversation — so this single marker makes every tool round and every
        // follow-up question re-read the whole prefix at the cached rate.
        let system: [[String: Any]] = [
            ["type": "text", "text": rules],
            ["type": "text", "text": data, "cache_control": ["type": "ephemeral"]],
        ]

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "system": system,
            "output_config": ["effort": "medium"],
            // Route around a safety refusal rather than dead-ending the user.
            "betas": ["server-side-fallback-2026-07-01"],
            "fallbacks": "default",
            "messages": messages,
        ]
        if offersTools { body["tools"] = [CoachTools.schema] }
        return body
    }
}
