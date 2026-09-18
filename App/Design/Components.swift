import SwiftUI
import Charts

// MARK: - Signal identity

/// Each signal gets its own hue and its own sky. Distinct enough to recognise at a
/// glance, and shared across the card, the ring and the detail screen so the three
/// read as one object rather than three.
enum Signal: String, CaseIterable, Identifiable {
    case readiness, sleep, load
    var id: String { rawValue }

    var title: String {
        switch self {
        case .readiness: return "Readiness"
        case .sleep: return "Sleep"
        case .load: return "Load"
        }
    }

    var symbol: String {
        switch self {
        case .readiness: return "waveform.path.ecg"
        case .sleep: return "moon.stars"
        case .load: return "flame"
        }
    }

    var ring: [Color] {
        switch self {
        case .readiness: return [Tokens.readinessLow, Tokens.readinessHigh]
        case .sleep:     return [Tokens.sleepLow, Tokens.sleepHigh]
        case .load:      return [Tokens.loadLow, Tokens.loadHigh]
        }
    }

    /// The soft sky behind a detail screen.
    var sky: [Color] {
        switch self {
        case .readiness: return [Tokens.skyReadinessTop, Tokens.skyReadinessBottom]
        case .sleep:     return [Tokens.skySleepTop, Tokens.skySleepBottom]
        case .load:      return [Tokens.skyLoadTop, Tokens.skyLoadBottom]
        }
    }
}

/// A soft vertical wash, fading into the canvas so the page still feels like one surface.
struct SkyBackground: View {
    let signal: Signal

    var body: some View {
        ZStack {
            Tokens.canvas
            LinearGradient(colors: signal.sky + [Tokens.canvas],
                           startPoint: .top, endPoint: .bottom)
                .frame(maxHeight: 420)
                .frame(maxHeight: .infinity, alignment: .top)
                .blur(radius: 24)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Ring

/// A progress arc. The number in the middle is a percentile against the user's own
/// history — a real quantity — not an invented score out of a hundred.
struct RingGauge: View {
    let signal: Signal
    /// nil means there is not enough history to say — which is different from zero.
    let percent: Int?
    var caption: String?
    var lineWidth: CGFloat = 10
    var showsTitle = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated = false

    /// A genuinely terrible day still draws a visible nub. An empty ring reads as
    /// "broken", not as "bottom of your range".
    private static let minimumVisibleArc = 0.018

    /// `+` binds tighter than `??`, so this is spelled out rather than inlined.
    private var accessibilityText: String {
        let head = percent.map { "\(signal.title), \($0) percent" }
            ?? "\(signal.title), not enough history yet"
        return head + (caption.map { ", \($0)" } ?? "")
    }

    private var fraction: Double {
        guard let percent else { return 0 }
        return max(Self.minimumVisibleArc, Double(max(0, min(100, percent))) / 100)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Tokens.ringTrack, style: StrokeStyle(lineWidth: lineWidth,
                                                                 lineCap: .round))
                Circle()
                    .trim(from: 0, to: animated ? fraction : 0)
                    .stroke(
                        AngularGradient(colors: signal.ring + [signal.ring[0]],
                                        center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text(percent.map(String.init) ?? "—")
                        .font(.system(size: lineWidth * 3.0, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Tokens.textPrimary)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    if let caption {
                        Text(caption)
                            .font(.system(size: max(9, lineWidth * 0.95)))
                            .foregroundStyle(Tokens.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(lineWidth * 1.6)
            }
            .aspectRatio(1, contentMode: .fit)

            if showsTitle {
                Text(signal.title)
                    .font(.footnote)
                    .foregroundStyle(Tokens.textSecondary)
            }
        }
        .onAppear {
            guard !animated else { return }
            if reduceMotion { animated = true }
            else { withAnimation(.easeOut(duration: 0.7).delay(0.05)) { animated = true } }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

// MARK: - Stat chip

/// The small labelled figures under a hero ring. Icon, label, value — one idea each.
struct StatChip: View {
    let symbol: String
    let label: String
    let value: String
    var tint: Color = Tokens.textSecondary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Tokens.textSecondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(.title3, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }
}

/// A trend line, not decoration. No axes, no grid — the shape is the point.
struct Sparkline: View {
    let values: [Double]
    var tint: Color = Tokens.accent

    var body: some View {
        if values.count < 2 {
            Text("Not enough history yet").qualifier()
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

/// The callout that carries what to actually do. Deliberately the loudest block on
/// any screen it appears on.
struct CoachingBlock: View {
    let title: String
    let message: String
    var footnote: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(Tokens.textSecondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Tokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.cardRadius))
    }
}
