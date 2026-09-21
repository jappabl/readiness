import Foundation

/// A piece of an answer: prose, or a chart the app draws from data it already holds.
public enum CoachSegment: Equatable, Sendable {
    case text(String)
    case chart(MetricKind)
}

/// Turns an answer into prose and charts.
///
/// Charts are asked for with a marker in the text — `[chart:hrv]` — rather than with a
/// tool call. A tool call would mean a second request: the whole prefix read again and
/// another round trip before the first word appears. The marker costs about six tokens
/// and no round trip at all, and it is *cheaper than the prose it replaces*, since a
/// sentence describing a two-week trend runs three or four times longer.
///
/// The model never sends any data for the chart. It names a metric; the app draws it
/// from the history already on the device. Nothing extra crosses the wire in either
/// direction.
public enum CoachSegments {

    static let opening = "[chart:"

    public static func parse(_ text: String) -> [CoachSegment] {
        var segments: [CoachSegment] = []
        var pending = ""

        // A blank line is a new message, not a new line. Somebody answering on their
        // phone sends "Yes, but lighter." and then, a beat later, what to do about it;
        // three lines stacked in one bubble is a memo, and no amount of good writing
        // inside it reads as a person. A single newline is only wrapping and stays put.
        func flush() {
            for run in pending.components(separatedBy: "\n\n") {
                let trimmed = run.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { segments.append(.text(trimmed)) }
            }
            pending = ""
        }

        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "[" else {
                pending.append(text[index])
                index = text.index(after: index)
                continue
            }

            let rest = text[index...]
            guard let close = rest.firstIndex(of: "]") else {
                // No closing bracket yet. Either the marker is still arriving one
                // character at a time, or this is an ordinary bracket at the end of the
                // text. Holding it back costs nothing; showing "[cha" does.
                if rest.hasPrefix(opening) || opening.hasPrefix(String(rest)) { break }
                pending.append(contentsOf: rest)
                break
            }

            guard rest.hasPrefix(opening) else {
                // An ordinary bracket, like a set count. Leave it exactly as written.
                pending.append(text[index])
                index = text.index(after: index)
                continue
            }

            flush()
            let name = String(rest[rest.index(rest.startIndex, offsetBy: opening.count)..<close])
            if let kind = MetricKind(rawValue: name) {
                segments.append(.chart(kind))
            }
            // An unknown metric leaves nothing behind: the marker is the model's
            // shorthand, and showing it raw would be showing the user our plumbing.
            index = text.index(after: close)
        }

        flush()
        return segments
    }
}
