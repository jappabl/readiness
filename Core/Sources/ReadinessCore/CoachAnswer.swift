import Foundation

/// Splits an answer into the line that carries it and the detail behind it.
///
/// The first line is the only part most people read, so it is styled as the headline it
/// is rather than as the opening of a paragraph. Doing that in the view means finding
/// the sentence boundary here — and finding it without tripping on "14.2 ms", which is
/// the failure that matters, since almost every answer names a measurement.
public enum CoachAnswer {

    public static func split(_ text: String) -> (lead: String, body: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }

        var cut: String.Index?
        var index = trimmed.startIndex
        while index < trimmed.endIndex {
            let character = trimmed[index]
            if character.isNewline {
                cut = index
                break
            }
            if character == "." || character == "!" || character == "?" {
                let next = trimmed.index(after: index)
                // A full stop only ends a sentence when something other than a digit
                // follows it. Otherwise every decimal in the answer splits the lead.
                if next == trimmed.endIndex || trimmed[next].isWhitespace {
                    cut = next
                    break
                }
            }
            index = trimmed.index(after: index)
        }

        // Mid-stream there is often no boundary yet; the whole fragment is the lead, and
        // it becomes the lead properly once the sentence lands.
        guard let cut else { return (trimmed, "") }

        return (String(trimmed[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines),
                String(trimmed[cut...]).trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
