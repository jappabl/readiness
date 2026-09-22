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

    /// What the number is, in one line, for somebody who has never seen it.
    ///
    /// One line, not a paragraph. The first draft ran to three sentences each and Jett
    /// carried them across the screen in a bubble half the height of the phone, which
    /// is a manual rather than an introduction. If somebody wants the mechanism there
    /// is a whole sheet of it behind the information button.
    ///
    /// Nothing in the app said this. Every explanation written so far describes what
    /// moved a score, which only helps once you already know what the score is. Hao's
    /// friend opened the app and did not know what strain meant.
    ///
    /// Said once, used everywhere: the insights sheet and Jett's walkthrough. A second
    /// set of words that only new users ever see is how the two drift apart.
    var meaning: String {
        switch self {
        case .strain: return "How hard your body worked today. It climbs as the day does."
        case .recovery: return "How ready you are this morning, against your own normal."
        case .sleep: return "Last night against what you needed, not a fixed eight hours."
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

    /// The ring's colours for a given score.
    ///
    /// Recovery and sleep carry a verdict, so they take it: a recovery of 13 used to
    /// draw in the same green as a recovery of 90, which put a healthy-looking ring
    /// directly above the words "keep it gentle today". Strain has no verdict: a hard
    /// day is not a bad day. So it keeps its own ramp and says intensity instead.
    func ring(forPercent percent: Int?) -> [Color] {
        // Sleep is always purple. It is the signal with the strongest identity in the
        // app and recolouring it by verdict cost more in recognition than it bought in
        // information: the number is right there. Strain keeps its own ramp because a
        // hard day is not a bad day. Recovery is the one that carries a verdict.
        guard self == .recovery, let percent else { return ring }
        switch percent {
        case 67...: return [Tokens.recoveryLow, Tokens.recoveryHigh, Tokens.recoveryDeep]
        case 34..<67: return [Tokens.strainHigh, Tokens.strainLow, Tokens.strainDeep]
        default: return [Tokens.alertSoft, Tokens.alert, Tokens.alertDeep]
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

/// The ring. A gradient arc on a light track, rounded caps, and, for strain, a
/// hatched remainder rather than a plain one.
struct RingGauge: View {
    let signal: Signal
    /// nil means not enough history to say, which is not the same as zero.
    let percent: Int?
    /// Where today is worth getting to, 0...100. Drawn as a mark on the track and never
    /// said in words: see `StrainScore.target(recovery:)`.
    var target: Double?
    var lineWidth: CGFloat = 11
    var figureSize: CGFloat = 22

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

            if let target, (0...100).contains(target) {
                GeometryReader { geometry in
                    let side = min(geometry.size.width, geometry.size.height)
                    Capsule()
                        .fill(Tokens.textPrimary.opacity(0.28))
                        .frame(width: 2, height: lineWidth + 5)
                        .offset(y: -(side - lineWidth) / 2)
                        .rotationEffect(.degrees(360 * target / 100))
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
            }

            Circle()
                .trim(from: 0, to: animated ? fraction : 0)
                .stroke(AngularGradient(colors: signal.ring(forPercent: percent), center: .center,
                                        startAngle: .degrees(0),
                                        // Compress the ramp into the drawn arc, so a
                                        // short ring still reaches its deepest colour.
                                        endAngle: .degrees(360 * max(0.12, fraction))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // The number and nothing else. The word under it repeated the ring's own
            // colour and the screen's own title, and it was a fixed word rather than a
            // verdict. "Recovered" sat under a recovery of 15, in green, because the
            // figure colour was the signal's identity rather than the day's news.
            Text(percent.map { "\($0)" } ?? "—")
                .font(.system(size: figureSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
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
///
/// Sleep draws its night's stages around the ring rather than one plain arc. It is the
/// one signal whose parts people actually want to see, and the shape was already there
/// doing nothing with them.
struct HeroRing: View {
    let signal: Signal
    let percent: Int?
    var target: Double?
    var stages: SleepStages?

    var body: some View {
        ZStack {
            Circle()
                .fill(Tokens.surface)
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 6)
            if let stages {
                SleepStageRing(stages: stages, value: percent.map(Double.init),
                               lineWidth: 17, figureSize: 40)
                    .padding(11)
            } else {
                RingGauge(signal: signal, percent: percent, target: target,
                          lineWidth: 17, figureSize: 40)
                    .padding(11)
            }
        }
        .frame(width: 196, height: 196)
    }
}

// MARK: - Cards

/// Small icon and label, then a large value with its unit: the Bevel stat card.
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
    /// The metric this card is showing, when there is one worth explaining.
    var explains: MetricKind?

    enum Trend { case up, down }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11))
                Text(label).font(.system(size: 13))
                    .foregroundStyle(Tokens.textSecondary)
                if let explains {
                    Spacer(minLength: 0)
                    InfoButton(explains)
                        .padding(.trailing, -9)
                        .padding(.vertical, -9)
                }
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
    /// Head room for a card resting on top of this one. Nil when it stands alone.
    var topInset: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // His face rather than the word "Coaching", and beside what he said rather
            // than over it. The label was naming the obvious, and a heading above a
            // sentence he wrote reads as a section of a report. Alongside, it reads as
            // him saying it.
            HStack(alignment: .top, spacing: 10) {
                JettFace(size: 24)
                Text(message)
                    .font(.system(size: 15))
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .padding(.top, topInset ?? 0)

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
                    // Neutral: the tint stays on the disc behind it and on the badge.
                    .overlay(Image(systemName: symbol).font(.system(size: 16))
                        .foregroundStyle(Tokens.textPrimary))
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .offset(x: -1, y: 5)
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

/// Icon, label, chevron. The reference's one interactive idiom: it never uses a
/// filled button inside a card.
struct AccessoryRow: View {
    let symbol: String
    let label: String
    var tint: Color = Tokens.textPrimary
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.selected()
            action()
        } label: {
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

/// A card whose children are separated by hairlines rather than gaps: used wherever
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

/// The full-width action. Used sparingly: the reference prefers accessory rows.
struct PrimaryButton: View {
    let label: String
    var symbol: String?
    /// Ink by default, not the accent. A full-width fill in a saturated brand colour
    /// reads as shouting; the same colour on an icon beside it reads as expensive.
    var tint: Color = Tokens.action
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button {
            // The full-width action is a commit rather than a selection, so it gets the
            // middle tier: something is about to happen, not something has been picked.
            Haptics.light()
            action()
        } label: {
            HStack(spacing: 7) {
                if let symbol { Image(systemName: symbol).font(.subheadline.weight(.semibold)) }
                Text(label).font(.body.weight(.semibold))
            }
            .foregroundStyle(Tokens.onAction)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(enabled ? tint : Tokens.ringTrack,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            // No coloured glow under an ink button; the contrast is the emphasis.
            .shadow(color: .black.opacity(enabled ? 0.16 : 0), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

extension View {
    /// A tick whenever this value changes, which is what makes a wheel feel like a dial
    /// and a segmented control feel like a switch. Skipped on the first render, so a
    /// screen appearing does not buzz.
    func ticksOnChange<Value: Equatable>(_ value: Value) -> some View {
        onChange(of: value) { _, _ in Haptics.selected() }
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

/// A trend line with no axes: the shape is the point.
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

/// A line that draws itself, with the value at the drawing head available as it goes.
///
/// The line is built point by point rather than trimmed, because trimming walks arc
/// length and the number would drift out of step with the tip on steep sections. Here
/// the head position and the number come from the same fraction, so the figure is
/// always exactly the value under the dot.
struct DrawingLine<Header: View>: View {
    let values: [Double]
    var tint: Color = Tokens.accent
    var duration: Double = 1.7
    var lineHeight: CGFloat = 44
    /// Rendered inside the same timeline as the line, and handed the value under the
    /// head. It has to live in here: writing that value out to a `@State` every frame
    /// makes SwiftUI complain about updating more than once per frame, and it did.
    @ViewBuilder var header: (Double) -> Header

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()
    @State private var finished = false

    var body: some View {
        TimelineView(.animation(paused: finished || reduceMotion)) { context in
            let fraction = reduceMotion ? 1 : eased(rawFraction(at: context.date))
            VStack(alignment: .leading, spacing: 8) {
                header(value(at: fraction))
                Canvas { canvas, size in
                    guard values.count >= 2 else { return }
                    let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 4)
                    canvas.stroke(path(in: rect, upTo: fraction),
                                  with: .color(tint),
                                  style: StrokeStyle(lineWidth: 2, lineCap: .round,
                                                     lineJoin: .round))
                    if fraction > 0, fraction < 1,
                       let head = headPoint(in: rect, at: fraction) {
                        let dot = CGRect(x: head.x - 3, y: head.y - 3, width: 6, height: 6)
                        canvas.fill(Path(ellipseIn: dot), with: .color(tint))
                    }
                }
                .frame(height: lineHeight)
            }
        }
        .onAppear { started = Date() }
        .task {
            guard !reduceMotion else { finished = true; return }
            try? await Task.sleep(for: .seconds(duration))
            finished = true
        }
    }

    private func rawFraction(at date: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(started) / duration))
    }

    private func eased(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    private var span: (low: Double, high: Double) {
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        return high > low ? (low, high) : (low - 1, high + 1)
    }

    private func point(_ index: Int, _ rect: CGRect) -> CGPoint {
        let (low, high) = span
        let x = rect.minX + rect.width * Double(index) / Double(values.count - 1)
        let y = rect.maxY - rect.height * (values[index] - low) / (high - low)
        return CGPoint(x: x, y: y)
    }

    /// Everything up to the head, with the final segment cut at the exact fraction.
    private func path(in rect: CGRect, upTo fraction: Double) -> Path {
        var path = Path()
        let head = fraction * Double(values.count - 1)
        let whole = Int(head.rounded(.down))
        path.move(to: point(0, rect))
        if whole >= 1 {
            for index in 1...whole { path.addLine(to: point(index, rect)) }
        }
        let remainder = head - Double(whole)
        if remainder > 0, whole + 1 < values.count {
            let from = point(whole, rect), to = point(whole + 1, rect)
            path.addLine(to: CGPoint(x: from.x + (to.x - from.x) * remainder,
                                     y: from.y + (to.y - from.y) * remainder))
        }
        return path
    }

    private func headPoint(in rect: CGRect, at fraction: Double) -> CGPoint? {
        guard values.count >= 2 else { return nil }
        let head = fraction * Double(values.count - 1)
        let whole = Int(head.rounded(.down))
        guard whole + 1 < values.count else { return point(values.count - 1, rect) }
        let from = point(whole, rect), to = point(whole + 1, rect)
        let remainder = head - Double(whole)
        return CGPoint(x: from.x + (to.x - from.x) * remainder,
                       y: from.y + (to.y - from.y) * remainder)
    }

    /// The reading under the head, interpolated so the figure moves smoothly.
    private func value(at fraction: Double) -> Double {
        guard values.count >= 2 else { return values.first ?? 0 }
        let head = fraction * Double(values.count - 1)
        let whole = Int(head.rounded(.down))
        guard whole + 1 < values.count else { return values[values.count - 1] }
        let remainder = head - Double(whole)
        return values[whole] + (values[whole + 1] - values[whole]) * remainder
    }
}

/// A quiet "what is this" on a number that needs one.
///
/// Deliberately low contrast and small: it should be findable when you want it and
/// invisible when you do not. A screen where every value shouts for attention has no
/// hierarchy left.
struct InfoButton: View {
    let title: String
    let explanation: String

    @State private var showing = false

    var body: some View {
        Button {
            Haptics.selected()
            showing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13))
                .foregroundStyle(Tokens.textSecondary.opacity(0.45))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What is \(title)?")
        .popover(isPresented: $showing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Tokens.textPrimary)
                    Text(explanation)
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: 290)
            .frame(maxHeight: 420)
            // The host of this button is often a card that clamps itself to one line,
            // and that clamp reaches into the popover and truncates the explanation.
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
            // A popover, not a sheet: an explanation is an aside, and a sheet makes it
            // feel like somewhere you have gone.
            .presentationCompactAdaptation(.popover)
        }
    }
}

extension InfoButton {
    init(_ kind: MetricKind) {
        self.init(title: kind.displayName, explanation: kind.explanation)
    }
}

// MARK: - The bar

/// Jett, as a face.
///
/// He was a ring for a while, and the ring was wrong. It was clean and it said nothing:
/// this app is already made of rings, so one more reads as a gauge rather than as a
/// person. A face is the only element here somebody could feel they are talking to,
/// which is the entire job of a coach.
struct JettFace: View {
    var size: CGFloat = 38

    var body: some View {
        Image("JettFace")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .accessibilityHidden(true)
    }
}


/// Jett, standing there, for the screens that would otherwise be empty.
///
/// A blank page reads as a failure. Every one of these screens is legitimately empty,
/// a day with nothing recorded, a Train tab before there is a plan, and the app was
/// saying so with a line of grey text in the middle of nothing, which looks like
/// something went wrong rather than like there is nothing here yet.
///
/// A body rather than the face, because the face is an avatar: it belongs beside a
/// sentence he is saying. Somebody standing in an empty room is the thing that makes
/// the room read as waiting rather than broken, and it needs legs to do that.
struct JettStanding: View {
    var height: CGFloat = 190

    var body: some View {
        Image("JettBody")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

/// Him, a line about why there is nothing here, and whatever gets you out of it.
///
/// One per screen, never per section. A Train tab with no split and no history has two
/// empty sections and wants one Jett; three of him stacked down a page is a mascot
/// problem rather than an empty-state one.
struct EmptyStateView<Actions: View>: View {
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 16) {
            JettStanding()
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Tokens.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)
            actions()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(message: String) {
        self.init(message: message) { EmptyView() }
    }
}


/// Five slots on a floating surface, the middle one being the coach.
///
/// The coach sits in the bar rather than over it because it is a destination like any
/// other, not something hovering in front of your reading.
/// A section heading with the explanation tucked behind it.
///
/// A paragraph under a control is a paragraph everybody scrolls past to reach the thing
/// itself, and if it only restates what the control obviously does it should not exist
/// at all. What survives that test is usually a promise the UI cannot make on its own,
/// where data goes, what the app will not do, and that belongs one tap away, not in
/// everybody's way.
struct InfoDot: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button {
            Haptics.selected()
            showing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 13, weight: .medium))
                // Neutral, like every other icon. Nothing here is good or bad news.
                .foregroundStyle(Tokens.textSecondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About this")
        .popover(isPresented: $showing) {
            // Scrollable, because a popover clips rather than grows. A long enough
            // explanation lost its first line and its last: a tester opened the one
            // setting that says when Jett messages you, found it truncated at both ends
            // with nothing to scroll, and wrote that he could not read the only thing he
            // came to Profile for.
            ScrollView {
                Text(text)
                    .font(.system(size: 15))
                    .lineSpacing(3)
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(width: 292)
            .frame(maxHeight: 420)
            .presentationCompactAdaptation(.popover)
        }
    }
}

/// A heading, optionally with one of those.
struct SectionHeadingRow: View {
    let title: String
    var info: String?

    var body: some View {
        HStack(spacing: 2) {
            Text(title).sectionHeading()
            if let info, !info.isEmpty { InfoDot(text: info) }
            Spacer(minLength: 0)
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selection: Int
    var onAsk: () -> Void
    /// Held rather than tapped. Speaking is what you want when your hands are busy,
    /// which is also when you are least able to aim at a small target.
    var onTalk: () -> Void = {}

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
        Button {
            // Only on an actual move. Tapping the tab you are already on changes
            // nothing, and a buzz for nothing is how haptics stop meaning anything.
            guard selection != tag else { return }
            Haptics.light()
            selection = tag
        } label: {
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

    /// The one slot with a face in it and no word under it.
    ///
    /// Everything either side is an outline glyph with a label; this is a person. The
    /// asymmetry is the point: you do not need telling twice what it is, and the missing
    /// label is what makes the slot read as somebody rather than as a destination.
    private var ask: some View {
        Button { Haptics.light(); onAsk() } label: {
            JettFace(size: 38)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        // Long press before the tap, so holding never also opens the chat behind it.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                Haptics.committed()
                onTalk()
            })
        .accessibilityLabel("Ask Coach Jett")
        .accessibilityHint("Double tap and hold to say a set out loud")
        // VoiceOver cannot perform a long press, so the same door is an action here.
        .accessibilityAction(named: "Say a set") { onTalk() }
    }
}

extension View {
    /// Leaves room for the floating tab bar. Every scrolling tab needs this; see
    /// `Tokens.tabBarClearance` for why the safe area does not do it for them.
    func clearsTabBar() -> some View { padding(.bottom, Tokens.tabBarClearance) }
}
