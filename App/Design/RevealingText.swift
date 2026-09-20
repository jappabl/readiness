import SwiftUI

/// Text that arrives a word at a time.
///
/// A bubble that fades in whole is a card appearing. Words landing in sequence is
/// somebody speaking, and that difference is most of why the onboarding reads as a
/// conversation rather than a form with a face on it.
///
/// Deliberately quick. The pacing between messages already gives each one room; this is
/// the last fraction of a second, not a typewriter. Anything slower turns a four
/// question flow into a thing you wait through.
struct RevealingText: View {
    let text: String
    /// How long the whole sentence takes to land, however many words it has.
    var duration: Double = 0.34

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = 0

    private var words: [Substring] { text.split(separator: " ", omittingEmptySubsequences: false) }

    var body: some View {
        // Laid out as one wrapping paragraph rather than a stack of word views, so the
        // line breaks are the same before and after the reveal and nothing reflows.
        Text(attributed)
            .task(id: text) {
                guard !reduceMotion else { revealed = words.count; return }
                revealed = 0
                let step = UInt64((duration / Double(max(words.count, 1))) * 1_000_000_000)
                for index in words.indices {
                    try? await Task.sleep(nanoseconds: step)
                    // Cancelled mid-sentence, because the view scrolled away or the
                    // text changed under it. Show the whole thing rather than leaving
                    // half of it clear: an unfinished reveal is invisible text, which
                    // is a far worse failure than a missed animation.
                    guard !Task.isCancelled else { revealed = words.count; return }
                    withAnimation(.easeOut(duration: 0.18)) { revealed = index + 1 }
                }
            }
            .onDisappear { revealed = words.count }
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        for (index, word) in words.enumerated() {
            var piece = AttributedString(word)
            piece.foregroundColor = index < revealed ? Tokens.textPrimary : .clear
            result += piece
            if index < words.count - 1 { result += AttributedString(" ") }
        }
        return result
    }
}
