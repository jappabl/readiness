import SwiftUI
import Charts

// MARK: - Signal identity

enum Signal: String, CaseIterable, Identifiable {
    /// Declared in the order they sit across the top of Today.
    case strain, recovery, sleep
    var id: String { rawValue }

    var title: String {
        switch self {
        case .strain: return "Strain"
        case .recovery: return "Recovery"
        case .sleep: return "Sleep"
        }
    }

    /// The small word under the figure inside a hero ring.
    var heroWord: String {
        switch self {
        case .strain: return "Strain"
        case .recovery: return "Recovered"
        case .sleep: return "Sleep"
        }
    }

    /// Light at the arc's start, deepest at its tip.
    var ring: [Color] {
        switch self {
        case .strain:   return [Tokens.strainHigh, Tokens.strainLow, Tokens.strainDeep]
        case .recovery: return [Tokens.recoveryLow, Tokens.recoveryHigh, Tokens.recoveryDeep]
        case .sleep:    return [Tokens.sleepHigh, Tokens.sleepLow, Tokens.sleepDeep]
        }
    }

    /// The figure's own colour inside the hero ring.
    var figure: Color {
        switch self {
        case .strain: return Tokens.strainDeep
        case .recovery: return Tokens.recoveryDeep
        case .sleep: return Tokens.sleepDeep
        }
    }

    var sky: [Color] {
        switch self {
        case .strain:   return [Tokens.skyStrainTop, Tokens.skyStrainMid, Tokens.skyStrainBottom]
        case .recovery: return [Tokens.skyRecoveryTop, Tokens.skyRecoveryMid, Tokens.skyRecoveryBottom]
        case .sleep:    return [Tokens.skySleepTop, Tokens.skySleepMid, Tokens.skySleepBottom]
        }
    }

    /// Strain draws its unfilled remainder as hatching rather than a plain track.
    var hatchesRemainder: Bool { self == .strain }
}

/// The soft photographic wash behind a detail screen, fading into the canvas.
struct SkyBackground: View {
    let signal: Signal

    var body: some View {
        ZStack(alignment: .top) {
            Tokens.canvas
            LinearGradient(stops: [
                .init(color: signal.sky[0], location: 0.00),
                .init(color: signal.sky[1], location: 0.42),
                .init(color: signal.sky[2], location: 0.72),
                .init(color: Tokens.canvas, location: 1.00),
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: 460)
            .blur(radius: 18)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Ring

/// The ring. A gradient arc on a light track, rounded caps, and — for strain — a
/// hatched remainder rather than a plain one.
struct RingGauge: View {
    let signal: Signal
    /// nil means not enough history to say, which is not the same as zero.
    let percent: Int?
    var lineWidth: CGFloat = 11
    var figureSize: CGFloat = 22
    var showsHeroWord = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated = false

    private static let minimumVisibleArc = 0.02

    private var fraction: Double {
        guard let percent else { return 0 }
        return max(Self.minimumVisibleArc, Double(max(0, min(100, percent))) / 100)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Tokens.ringTrack, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            if signal.hatchesRemainder, percent != nil {
                Circle()
                    .trim(from: fraction, to: 1)
                    .stroke(signal.ring[1].opacity(0.55),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt,
                                               dash: [1.6, 3.4]))
                    .rotationEffect(.degrees(-90))
            }

            Circle()
                .trim(from: 0, to: animated ? fraction : 0)
                .stroke(AngularGradient(colors: signal.ring, center: .center,
                                        startAngle: .degrees(0),
                                        // Compress the ramp into the drawn arc, so a
                                        // short ring still reaches its deepest colour.
                                        endAngle: .degrees(360 * max(0.12, fraction))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            VStack(spacing: -1) {
                Text(percent.map { "\($0)" } ?? "—")
                    .font(.system(size: figureSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(showsHeroWord ? signal.figure : Tokens.textPrimary)
                + Text(percent == nil ? "" : "%")
                    .font(.system(size: figureSize * 0.62, weight: .semibold))
                    .foregroundStyle(showsHeroWord ? signal.figure : Tokens.textPrimary)

                if showsHeroWord {
                    Text(signal.heroWord)
                        .font(.system(size: figureSize * 0.34))
                        .foregroundStyle(Tokens.textSecondary)
                }
            }
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(lineWidth * 1.9)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            guard !animated else { return }
            if reduceMotion { animated = true }
            else { withAnimation(.easeOut(duration: 0.8).delay(0.05)) { animated = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(percent.map { "\(signal.title), \($0) percent" }
                            ?? "\(signal.title), not enough history yet")
    }
}

/// The hero ring on a detail screen, seated on a raised white disc.
struct HeroRing: View {
    let signal: Signal
    let percent: Int?

    var body: some View {
        ZStack {
            Circle()
                .fill(Tokens.surface)
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 6)
            RingGauge(signal: signal, percent: percent, lineWidth: 17,
                      figureSize: 40, showsHeroWord: true)
                .padding(11)
        }
        .frame(width: 196, height: 196)
    }
}

// MARK: - Cards

/// Small icon and label, then a large value with its unit — the Bevel stat card.
struct StatCard: View {
    let symbol: String
    let label: String
    let value: String
    var unit: String?
    var trend: Trend?
    /// Direction and valence are separate facts. A resting heart rate can point up
    /// while pointing up is the bad news, so the arrow and its colour are set apart.
    var trendFavourable = true
    /// When present, the card shows where the reading sits in the user's own range.
    var range: (z: Double, polarity: Double, tint: Color)?
    var status: String?

    enum Trend { case up, down }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                Text(label).font(.system(size: 13))
            }
            .foregroundStyle(Tokens.textSecondary)
            .lineLimit(1)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textPrimary)
                if let unit {
                    Text(unit).font(.system(size: 14)).foregroundStyle(Tokens.textSecondary)
                }
                Spacer(minLength: 0)
                if let trend {
                    Image(systemName: trend == .up ? "arrowtriangle.up.fill"
                                                   : "arrowtriangle.down.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(trendFavourable ? Tokens.positive : Tokens.negative)
                }
            }
            .minimumScaleFactor(0.6)
            .lineLimit(1)

            if let range {
                RangeBar(z: range.z, polarity: range.polarity, tint: range.tint)
                    .padding(.top, 1)
            }
            if let status {
                Text(status).font(.system(size: 12)).foregroundStyle(Tokens.textSecondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .bevelCard(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value) \(unit ?? "")" + (status.map { ", \($0)" } ?? ""))
    }
}

/// COACHING label over a short paragraph. The only prose on the screen.
struct CoachCard: View {
    let message: String
    var accessory: (label: String, symbol: String)?
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Coaching").microLabel()
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)

            if let accessory {
                Divider().overlay(Tokens.hairline)
                Button { action?() } label: {
                    HStack(spacing: 7) {
                        Image(systemName: accessory.symbol).font(.system(size: 13))
                        Text(accessory.label).font(.system(size: 15))
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 13))
                    }
                    .foregroundStyle(Tokens.textPrimary)
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.cardRadius,
                                                         style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }
}

/// A row in a Timeline list: badged icon, title, timestamp, chevron.
struct TimelineRow: View {
    let symbol: String
    let badge: String?
    let title: String
    let subtitle: String
    var tint: Color = Tokens.sleepLow

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 38, height: 38)
                    .overlay(Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(tint))
                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Tokens.onAccent)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(tint, in: Capsule())
                        .offset(x: -3, y: 4)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tokens.textPrimary)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13))
                .foregroundStyle(Tokens.textSecondary)
        }
        .bevelCard(padding: 12)
        .accessibilityElement(children: .combine)
    }
}
struct RangeBar: View {
    let z: Double
    let polarity: Double
    var tint: Color = Tokens.accent

    private var position: Double {
        let aligned = max(-3, min(3, z * polarity))
        return (aligned + 3) / 6
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Tokens.ringTrack)
                    .frame(height: 4)
                // The baseline itself, so the dot's distance from it is the message.
                // A tinted track glowed in the middle, which said the usual range was
                // the alarming part.
                Capsule()
                    .fill(Tokens.textSecondary.opacity(0.45))
                    .frame(width: 1.5, height: 9)
                    .offset(x: width / 2 - 0.75)
                Circle()
                    .fill(tint)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Tokens.surface, lineWidth: 2))
                    .offset(x: (width - 9) * position)
            }
            .frame(height: 10)
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// Icon, label, chevron. The reference's one interactive idiom — it never uses a
/// filled button inside a card.
struct AccessoryRow: View {
    let symbol: String
    let label: String
    var tint: Color = Tokens.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 13))
                Text(label).font(.system(size: 15))
                Spacer()
                Image(systemName: "arrow.right").font(.system(size: 13))
            }
            .foregroundStyle(tint)
            .padding(14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A card whose children are separated by hairlines rather than gaps — used wherever
/// the reference groups rows inside one surface.
struct ListCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.cardRadius,
                                                             style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
            .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }
}

/// The full-width action. Used sparingly — the reference prefers accessory rows.
struct PrimaryButton: View {
    let label: String
    var symbol: String?
    var tint: Color = Tokens.accent
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).font(.system(size: 14, weight: .semibold)) }
                Text(label).font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(Tokens.onAccent)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(enabled ? tint : Tokens.ringTrack,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: enabled ? tint.opacity(0.26) : .clear, radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// Key/value row inside a ListCard.
struct FieldRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(Tokens.textPrimary)
            Spacer(minLength: 12)
            trailing
                .font(.system(size: 15))
                .foregroundStyle(Tokens.textSecondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

/// A trend line with no axes — the shape is the point.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = Tokens.accent

    var body: some View {
        if values.count < 2 {
            Text("Not enough history yet")
                .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
        } else {
            Chart(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("Day", index), y: .value("Value", value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(tint)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .accessibilityHidden(true)
        }
    }
}

// MARK: - The bar

/// The ask, as a ring of light.
///
/// Built from the app's own grammar rather than an imported shape: everything here is
/// rings, so the coach is one too — thin, lit, and see-through, which lets it sit among
/// outline glyphs without bullying them the way a filled mark does. The sweep is a
/// deliberate non-spectrum; it belongs to no signal, so it never reads as a reading.
///
/// It turns while Jett is thinking. That is the whole personality: a mascot would have
/// to act, and this only has to move.
struct JettOrb: View {
    var size: CGFloat = 30
    var isThinking = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin: Double = 0

    private var sweep: AngularGradient {
        AngularGradient(stops: [
            .init(color: Color(red: 0.45, green: 0.36, blue: 0.96), location: 0.00),
            .init(color: Color(red: 0.24, green: 0.60, blue: 0.99), location: 0.28),
            .init(color: Color(red: 0.28, green: 0.86, blue: 0.87), location: 0.50),
            .init(color: Color(red: 0.99, green: 0.79, blue: 0.43), location: 0.75),
            .init(color: Color(red: 0.45, green: 0.36, blue: 0.96), location: 1.00),
        ], center: .center, angle: .degrees(-100))
    }

    var body: some View {
        ZStack {
            Group {
                // The glow is most of the effect: without it the ring reads as a sticker.
                Circle()
                    .strokeBorder(sweep, lineWidth: size * 0.30)
                    .blur(radius: size * 0.17)
                    .opacity(isThinking ? 0.8 : 0.55)

                Circle()
                    .strokeBorder(sweep, lineWidth: size * 0.19)
            }
            .rotationEffect(.degrees(spin))

            // The highlight stays put while the sweep turns under it — light does not
            // travel with the object it is falling on.
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .clear],
                                             startPoint: .top, endPoint: .center),
                              lineWidth: size * 0.06)
                .blur(radius: size * 0.022)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.3), value: isThinking)
        .onAppear { if isThinking { startSpinning() } }
        .onChange(of: isThinking) { _, thinking in
            if thinking { startSpinning() } else { withAnimation(.easeOut(duration: 0.4)) { spin = 0 } }
        }
    }

    private func startSpinning() {
        guard !reduceMotion else { return }
        spin = 0
        withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
            spin = 360
        }
    }
}

/// Five slots on a floating surface, the middle one being the coach.
///
/// The coach sits in the bar rather than over it because it is a destination like any
/// other, not something hovering in front of your reading.
struct FloatingTabBar: View {
    @Binding var selection: Int
    var onAsk: () -> Void

    static let height: CGFloat = 64

    var body: some View {
        HStack(spacing: 0) {
            item(0, "Today", "sun.max", "sun.max.fill")
            item(1, "Train", "dumbbell", "dumbbell.fill")
            ask
            item(2, "Trends", "chart.bar", "chart.bar.fill")
            item(3, "Profile", "person", "person.fill")
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.10), radius: 16, x: 0, y: 5)
        .shadow(color: .black.opacity(0.04), radius: 2, x: 0, y: 1)
        .padding(.horizontal, 12)
    }

    private func item(_ tag: Int, _ title: String, _ symbol: String, _ filled: String) -> some View {
        Button { selection = tag } label: {
            VStack(spacing: 3) {
                Image(systemName: selection == tag ? filled : symbol)
                    .font(.system(size: 18, weight: .medium))
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 10, weight: selection == tag ? .semibold : .medium))
            }
            .foregroundStyle(selection == tag ? Tokens.textPrimary : Tokens.textSecondary)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == tag ? [.isSelected, .isButton] : .isButton)
    }

    private var ask: some View {
        Button { Haptics.light(); onAsk() } label: {
            VStack(spacing: 3) {
                JettOrb(size: 28).frame(height: 22)
                // The name is the affordance — the ring says "something lives here",
                // the word says what. It carries the weight of a selected tab because
                // the coach is always available, never merely current.
                Text("Jett").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Ask Coach Jett")
    }
}
