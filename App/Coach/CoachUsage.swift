import Foundation
import os

/// What one request actually cost, in tokens.
///
/// This exists because the only way to keep a per-message bill small is to be able to
/// see it. `cacheRead` against `input` is the number that says whether prompt caching
/// is doing its job: on a follow-up question in the same conversation, almost the whole
/// prefix should be a cache read.
struct CoachUsage {
    private static let log = Logger(subsystem: "com.coachjett.ios", category: "coach")

    var input = 0
    var output = 0
    var cacheWrite = 0
    var cacheRead = 0

    mutating func absorb(_ reported: [String: Any]) {
        input      = (reported["input_tokens"] as? Int) ?? input
        output     = (reported["output_tokens"] as? Int) ?? output
        cacheWrite = (reported["cache_creation_input_tokens"] as? Int) ?? cacheWrite
        cacheRead  = (reported["cache_read_input_tokens"] as? Int) ?? cacheRead
    }

    /// Everything billed as input, however it was billed.
    var totalInput: Int { input + cacheWrite + cacheRead }

    /// What share of the input came back from cache. Nil before anything was sent.
    var cacheHitRate: Double? {
        guard totalInput > 0 else { return nil }
        return Double(cacheRead) / Double(totalInput)
    }

    func log() {
        let rate = cacheHitRate.map { String(format: "%.0f%%", $0 * 100) } ?? "—"
        Self.log.notice("""
            COACH USAGE in \(totalInput) (fresh \(input), cache write \(cacheWrite), \
            cache read \(cacheRead), hit \(rate)) · out \(output)
            """)
    }
}
