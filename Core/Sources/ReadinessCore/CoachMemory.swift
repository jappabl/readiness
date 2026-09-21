import Foundation

/// The handful of things Jett carries between conversations.
///
/// Almost nothing belongs here. Scores, load, sleep, the programme, the answers from
/// onboarding, all of it is rebuilt from the record and sent fresh with every message,
/// so writing any of it down would only create a second copy to go stale. What is left
/// is what nothing else records: a niggle mentioned in passing, a constraint with an end
/// date, something they asked not to be brought up again.
///
/// Small on purpose. A memory that grows without limit stops being memory and becomes a
/// second prompt, and every line in it is a line the day's own numbers have to compete
/// with for attention.
public struct CoachMemory: Equatable, Sendable, Codable {

    public struct Note: Equatable, Sendable, Codable, Identifiable {
        public let id: UUID
        public let text: String
        /// When it was last confirmed, not when it was first heard: a fact repeated
        /// today is a fact about today.
        public let written: Date

        public init(id: UUID = UUID(), text: String, written: Date) {
            self.id = id
            self.text = text
            self.written = written
        }
    }

    /// Twenty is not a budget, it is a definition. Somebody with fifty facts about them
    /// has a profile, not a memory, and Jett has no way to rank fifty.
    public static let capacity = 20
    public static let maximumNoteLength = 140
    public static let maximumBriefBytes = 1200

    public private(set) var notes: [Note] = []

    public init(notes: [Note] = []) {
        self.notes = notes
    }

    /// Writes a fact down, replacing one it supersedes. Returns nil when there was
    /// nothing to write.
    @discardableResult
    public mutating func remember(_ text: String, on date: Date) -> Note? {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(Self.maximumNoteLength))
        guard !trimmed.isEmpty else { return nil }

        let note = Note(text: trimmed, written: date)
        // A fact restated is the same fact. Without this the shoulder gets written down
        // every time it comes up and the list is one thing, six times.
        if let existing = notes.firstIndex(where: { Self.sameFact($0.text, trimmed) }) {
            notes.remove(at: existing)
        }
        notes.append(note)
        notes.sort { $0.written < $1.written }
        if notes.count > Self.capacity {
            notes.removeFirst(notes.count - Self.capacity)
        }
        return note
    }

    /// Dropped by naming it. Jett sees the notes as words, not as identifiers, and an
    /// id in the block is one more thing to copy down wrong.
    @discardableResult
    public mutating func forget(matching text: String) -> Note? {
        guard let index = notes.firstIndex(where: { Self.sameFact($0.text, text) }) else {
            return nil
        }
        return notes.remove(at: index)
    }

    @discardableResult
    public mutating func forget(id: UUID) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        notes.remove(at: index)
        return true
    }

    /// Oldest first, each with its age, so the freshest fact sits closest to the
    /// question and a stale one can be recognised as stale and dropped.
    public func brief(asOf date: Date) -> String {
        guard !notes.isEmpty else { return "" }
        var lines = ["what you have been told about this person, oldest first:"]
        for note in notes {
            lines.append("- \(Self.age(of: note.written, asOf: date)): \(note.text)")
        }
        var rendered = lines.joined(separator: "\n")
        // The day's own numbers matter more than anything written weeks ago, so the
        // block is cut from the oldest end rather than allowed to crowd them out.
        while rendered.utf8.count > Self.maximumBriefBytes, lines.count > 2 {
            lines.remove(at: 1)
            rendered = lines.joined(separator: "\n")
        }
        return rendered
    }

    // MARK: - Same fact, different words

    /// Two notes are the same fact when nearly all of the shorter one's words are in the
    /// longer. Exact matching is not enough: "clicks on overhead press" and "clicks when
    /// pressing overhead" are one niggle, and storing both is how the list fills up.
    static func sameFact(_ left: String, _ right: String) -> Bool {
        let a = significantWords(left), b = significantWords(right)
        guard let smaller = [a, b].min(by: { $0.count < $1.count }), !smaller.isEmpty else {
            return false
        }
        let shared = a.intersection(b).count
        return Double(shared) / Double(smaller.count) >= 0.7
    }

    /// Words that carry the fact. Dropping the joiners is what lets a rephrasing match:
    /// "on overhead press" and "when pressing overhead" differ mostly in them.
    private static let joiners: Set<String> = [
        "a", "an", "and", "as", "at", "be", "been", "but", "by", "can", "do", "does",
        "for", "from", "has", "have", "in", "into", "is", "it", "its", "of", "on", "or",
        "that", "the", "their", "them", "they", "this", "to", "until", "up", "was",
        "when", "which", "while", "with",
    ]

    private static func significantWords(_ text: String) -> Set<String> {
        let stripped = text.lowercased().map { $0.isLetter || $0.isNumber ? $0 : " " }
        return Set(String(stripped).split(separator: " ")
            .map { Self.stem(String($0)) }
            .filter { !$0.isEmpty && !joiners.contains($0) })
    }

    /// The crudest stem that does the job: "press", "presses" and "pressing" are one
    /// word here. Anything cleverer would be a linguistics project inside a gym app.
    private static func stem(_ word: String) -> String {
        for ending in ["ing", "es", "ed", "s"] where word.count > ending.count + 2 {
            if word.hasSuffix(ending) { return String(word.dropLast(ending.count)) }
        }
        return word
    }

    // MARK: - Age

    static func age(of written: Date, asOf now: Date) -> String {
        let days = Int((now.timeIntervalSince(written) / 86_400).rounded(.down))
        switch days {
        case ..<1: return "today"
        case 1: return "yesterday"
        case 2..<14: return "\(days) days ago"
        case 14..<60: return "\(days / 7) weeks ago"
        default: return "\(max(2, days / 30)) months ago"
        }
    }
}
