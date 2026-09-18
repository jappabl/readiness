import UIKit

/// Physical feedback at the moments that carry weight — a set landing, a decision
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

    /// The rest timer running out.
    static func restOver() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
