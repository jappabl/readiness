import UIKit

/// Physical feedback at the moments that carry weight: a set landing, a decision
/// taken, a change applied. Not on navigation, not on scrolling: haptics stop meaning
/// anything the moment everything buzzes.
enum Haptics {

    /// Something was committed: a set logged, a check-in saved, a change applied.
    static func committed() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A decision that reverses something, or overrides the app.
    static func decided() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// A surface opening or a selection landing.
    static func light() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// Jett starting to answer. Deliberately the faintest tap in the vocabulary: it
    /// fires on every reply, so anything stronger would wear out fast and drown the
    /// taps that mean something happened.
    static func replyBegan() {
        let generator = UIImpactFeedbackGenerator(style: .soft)
        generator.impactOccurred(intensity: 0.5)
    }

    /// Jett finished. A selection tick rather than a success notification: the answer
    /// arriving is not an achievement.
    static func replyEnded() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// The rest timer running out.
    static func restOver() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
