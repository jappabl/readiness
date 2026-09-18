import SwiftUI

/// Semantic tokens, resolved per appearance. No view ever hardcodes a hex (spec 9.1).
/// Light is the design target; dark must not break.
enum Tokens {

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Slightly warm off-white. Calmer than systemGroupedBackground, and a cheap point
    /// of difference — one of the three deliberate departures from stock (spec 9.7).
    static let canvas        = dynamic(light: 0xF4F4F2, dark: 0x131312)
    static let surface       = dynamic(light: 0xFFFFFF, dark: 0x1D1D1B)
    static let textPrimary   = dynamic(light: 0x1A1A18, dark: 0xF2F2EE)
    static let textSecondary = dynamic(light: 0x6B6B66, dark: 0x9A9A93)
    static let textTertiary  = dynamic(light: 0xA3A39D, dark: 0x6F6F69)
    static let hairline      = dynamic(light: 0xE5E5E1, dark: 0x2E2E2B)

    /// One accent. Interactive elements and the prescribed load, nothing else.
    /// Deliberately not a traffic-light hue: colour carries no meaning in the
    /// readiness display (spec 9.4).
    static let accent        = dynamic(light: 0x2F4858, dark: 0x8FB3C4)

    /// Reserved for Tier 2 threshold alerts. Unused in v0.1 — defined so that when an
    /// alert does fire it is the only warm colour on screen.
    static let alert         = dynamic(light: 0x9A5B20, dark: 0xD79A5B)

    static let cardRadius: CGFloat = 14
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

// MARK: - Type

extension View {
    /// 13pt semibold uppercase with generous tracking. Small-caps labels only (spec 9.2).
    func sectionHeader() -> some View {
        self.font(.system(.footnote, design: .default, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(Tokens.textSecondary)
    }

    /// Units and baselines: always adjacent to the value they qualify, never alone.
    func qualifier() -> some View {
        self.font(.system(.footnote, design: .default))
            .foregroundStyle(Tokens.textSecondary)
    }

    func card() -> some View {
        self.padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.cardRadius))
    }
}
