import SwiftUI

/// Palette and metrics traced from the reference screenshots.
enum Tokens {

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    // Native conversation surfaces follow Messages in both appearances.
    static let messageCanvas = Color(uiColor: .systemBackground)
    static let messageIncoming = Color(uiColor: .secondarySystemBackground)
    // Messages blue adjusted slightly for white body-text contrast.
    /// What you said, in Jett's colour rather than iMessage's. Also gains a dark
    /// variant it did not have: the old value was the same in both schemes and glared
    /// against the dark canvas.
    static let messageOutgoing = dynamic(light: 0x0A7AFF, dark: 0x4C9CFF)
    static let messageOnOutgoing = Color.white

    // Surfaces
    static let canvas        = dynamic(light: 0xF1F1F4, dark: 0x0E0E10)
    static let surface       = dynamic(light: 0xFFFFFF, dark: 0x1C1C1F)
    static let surfaceSunken  = dynamic(light: 0xF7F7F9, dark: 0x17171A)

    // Type
    static let textPrimary   = dynamic(light: 0x1C1C1E, dark: 0xF2F2F5)
    static let textSecondary = dynamic(light: 0x86868B, dark: 0x98989E)
    static let textTertiary  = dynamic(light: 0x6E6E73, dark: 0x8A8A90)
    static let hairline      = dynamic(light: 0xE8E8EC, dark: 0x2A2A2E)

    // Rings
    static let ringTrack     = dynamic(light: 0xEAEAEE, dark: 0x2C2C31)
    // Each ring runs light at the start of its arc to deep at the tip, so the end of
    // the drawn line is always the most saturated part of it.
    static let strainHigh    = dynamic(light: 0xFAD98A, dark: 0xFBE0A0)
    static let strainLow     = dynamic(light: 0xF0AE28, dark: 0xF5C045)
    static let strainDeep    = dynamic(light: 0xCE7A17, dark: 0xE09433)

    static let recoveryLow   = dynamic(light: 0xD6E356, dark: 0xDFE96E)
    static let recoveryHigh  = dynamic(light: 0x5FC22E, dark: 0x74D344)
    static let recoveryDeep  = dynamic(light: 0x2A9440, dark: 0x3FAF57)

    static let sleepHigh     = dynamic(light: 0xC0B4FB, dark: 0xCCC2FC)
    static let sleepLow      = dynamic(light: 0x8B78F0, dark: 0xA694F7)
    static let sleepDeep     = dynamic(light: 0x5B3FC4, dark: 0x7659DC)

    // Meaning
    /// Jett's colour, and the app's.
    ///
    /// Was green, then purple. Purple read bold at any size and sat a hue away from
    /// sleep's indigo, so the two were never properly distinct. Sleep took the purple
    /// instead, which suits it, and the brand took blue, which is calmer under a face
    /// that is meant to coach rather than impress. Nothing else in the app is blue now.
    static let accent        = dynamic(light: 0x0A7AFF, dark: 0x4C9CFF)
    static let onAccent      = dynamic(light: 0xFFFFFF, dark: 0x0E0E10)

    /// The thing you tap.
    ///
    /// No hue at all, and inverted between schemes so a primary action is never a grey
    /// slab on a black screen. Separating the action colour from the brand colour is
    /// what lets the accent stay saturated without a full-width button shouting: purple
    /// then appears only where it means something, and is the only colour on the screen
    /// when it does.
    static let action        = dynamic(light: 0x1C1C1E, dark: 0xF2F2F5)
    static let onAction      = dynamic(light: 0xFFFFFF, dark: 0x0E0E10)
    static let positive      = dynamic(light: 0x34A853, dark: 0x5BD45B)
    static let negative      = dynamic(light: 0xE9573F, dark: 0xF07A64)

    /// Pulled from the coach ring's sweep, for the few marks that belong to Jett
    /// rather than to the app. Keeps his surfaces off the brand green, which now reads
    /// as "an action you take" everywhere else.
    /// Kept as a name for the few places that mean "Jett specifically" rather than
    /// "an action". Same colour as the accent now, and deliberately one source of truth
    /// so the two can never drift apart.
    static let jettTint = accent

    // Skies behind the detail screens
    static let skyStrainTop      = dynamic(light: 0xCFE0EE, dark: 0x1B2430)
    static let skyStrainMid      = dynamic(light: 0xF6D3B0, dark: 0x2E2418)
    static let skyStrainBottom   = dynamic(light: 0xF4F1EE, dark: 0x191714)

    static let skyRecoveryTop    = dynamic(light: 0xB6D8EF, dark: 0x15222E)
    static let skyRecoveryMid    = dynamic(light: 0xD8EAF2, dark: 0x16262B)
    static let skyRecoveryBottom = dynamic(light: 0xEDF1F3, dark: 0x14181B)

    static let skySleepTop       = dynamic(light: 0xB3BCE8, dark: 0x171A2C)
    static let skySleepMid       = dynamic(light: 0xD8DDF4, dark: 0x1A1E33)
    static let skySleepBottom    = dynamic(light: 0xEFF0F5, dark: 0x15161C)

    static let cardRadius: CGFloat = 18
    static let screenMargin: CGFloat = 16
    static let cardGap: CGFloat = 12
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red:   CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue:  CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Shared chrome

extension View {
    /// The card treatment used throughout: white, generously rounded, and lifted by a
    /// shadow soft enough that you notice the edge rather than the shadow.
    func bevelCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.cardRadius,
                                                             style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }

    /// Small uppercase grey label above a block of copy.
    func microLabel() -> some View {
        self.font(.system(size: 12, weight: .medium))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(Tokens.textSecondary)
    }

    /// Kept for the screens that predate the card system.
    func sectionHeader() -> some View { microLabel() }

    func qualifier() -> some View {
        self.font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
    }

    func card() -> some View { bevelCard() }

    /// Bold dark section heading between cards.
    func sectionHeading() -> some View {
        self.font(.system(size: 18, weight: .bold))
            .foregroundStyle(Tokens.textPrimary)
    }
}
