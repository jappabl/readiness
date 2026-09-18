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
    /// Spec 9.1 names #A3A39D here, but that is 2.30:1 on the canvas and fails the
    /// contrast line of the 9.7 review checklist. The two cannot both hold, so the tier
    /// is kept and de-emphasis is carried by size and weight instead of colour alone.
    static let textTertiary  = dynamic(light: 0x70706A, dark: 0x8A8A84)
    static let hairline      = dynamic(light: 0xE5E5E1, dark: 0x2E2E2B)

    /// One accent. Interactive elements and the prescribed load, nothing else.
    /// Deliberately not a traffic-light hue: colour carries no meaning in the
    /// readiness display (spec 9.4).
    static let accent        = dynamic(light: 0x2F4858, dark: 0x8FB3C4)

    /// Label colour for filled accent surfaces. Without this, a prominent button in dark
    /// mode renders white on a light accent at 2.23:1.
    static let onAccent      = dynamic(light: 0xFFFFFF, dark: 0x131312)

    /// Reserved for Tier 2 threshold alerts. Unused in v0.1 — defined so that when an
    /// alert does fire it is the only warm colour on screen.
    static let alert         = dynamic(light: 0x9A5B20, dark: 0xD79A5B)

    /// Direction of travel on a trend. Colour here carries meaning, never decoration,
    /// and never encodes the recommendation itself.
    static let positive      = dynamic(light: 0x2E6B4F, dark: 0x7FC0A0)
    static let negative      = dynamic(light: 0x8C4A2F, dark: 0xD79A78)

    // MARK: - Signal hues
    //
    // One hue per signal, used on its ring and its sky. These identify *which* signal
    // you are looking at; they never encode whether the day is good or bad — that is
    // what the coaching card says in words.

    static let readinessLow  = dynamic(light: 0x3E9B7A, dark: 0x4FB894)
    static let readinessHigh = dynamic(light: 0x7FCFA4, dark: 0x93E0B8)
    static let sleepLow      = dynamic(light: 0x4F63B0, dark: 0x6E83D4)
    static let sleepHigh     = dynamic(light: 0x8AA2E8, dark: 0xA2B8F5)
    static let loadLow       = dynamic(light: 0xC97B3C, dark: 0xDE9457)
    static let loadHigh      = dynamic(light: 0xE9B06A, dark: 0xF2C68B)

    static let ringTrack     = dynamic(light: 0xE7E7E3, dark: 0x2B2B28)

    // Soft skies behind the detail screens.
    static let skyReadinessTop    = dynamic(light: 0xD6F0E2, dark: 0x16302A)
    static let skyReadinessBottom = dynamic(light: 0xF0F7F2, dark: 0x14201D)
    static let skySleepTop        = dynamic(light: 0xDCE3F7, dark: 0x1A2038)
    static let skySleepBottom     = dynamic(light: 0xF0F2FA, dark: 0x161A28)
    static let skyLoadTop         = dynamic(light: 0xFBE8D4, dark: 0x2E2318)
    static let skyLoadBottom      = dynamic(light: 0xFAF3EA, dark: 0x201A14)

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
