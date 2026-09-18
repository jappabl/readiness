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

    var ring: [Color] {
        switch self {
        case .strain:   return [Tokens.strainLow, Tokens.strainHigh]
        case .recovery: return [Tokens.recoveryLow, Tokens.recoveryHigh]
        case .sleep:    return [Tokens.sleepLow, Tokens.sleepHigh]
        }
    }

    /// The figure's own colour inside the hero ring.
    var figure: Color {
        switch self {
        case .strain: return Tokens.strainLow
        case .recovery: return Tokens.recoveryHigh
        case .sleep: return Tokens.sleepLow
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
                                        startAngle: .degrees(-4), endAngle: .degrees(320)),
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
                        .foregroundStyle(trend == .up ? Tokens.positive : Tokens.negative)
                }
            }
            .minimumScaleFactor(0.6)
            .lineLimit(1)
        }
        .bevelCard(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value) \(unit ?? "")")
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

/// The segmented energy meter from the reference — discrete ticks, filled to a share.
struct SegmentedMeter: View {
    let fraction: Double
    let symbol: String
    var tint: Color = Tokens.accent
    private let segments = 34

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(tint)
            GeometryReader { geometry in
                let filled = Int((Double(segments) * max(0, min(1, fraction))).rounded())
                HStack(spacing: 2) {
                    ForEach(0..<segments, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(index < filled ? tint : Tokens.ringTrack)
                            .frame(width: max(1.5, geometry.size.width / Double(segments) - 2))
                    }
                }
                .frame(height: 18)
            }
            .frame(height: 18)
            Text("\(Int((fraction * 100).rounded()))%")
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
        }
        .bevelCard(padding: 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int((fraction * 100).rounded())) percent")
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
