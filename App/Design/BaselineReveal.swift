import SwiftUI

/// The end of onboarding, where Jett shows somebody their own normal.
///
/// The sentence above it says "that's your normal now". A line does not show a normal,
/// so this draws the thing the sentence is actually claiming: every reading as a faint
/// point, the band those points fall inside, and the most recent one picked out against
/// it. Nothing here is illustrative. If the readings are not there, the card is not
/// there either.
struct BaselineReveal: View {
    let kind: MetricKind
    /// Oldest first.
    let values: [Double]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: Double = 0

    private var summary: BaselineSummary? { BaselineSummary.of(values) }

    var body: some View {
        if let summary, let latest = values.last(where: { $0.isFinite }) {
            VStack(alignment: .leading, spacing: 12) {
                header(summary)
                Canvas { context, size in
                    draw(context, size: size, summary: summary, latest: latest)
                }
                .frame(height: 132)
                .accessibilityHidden(true)
                footer(summary, latest: latest)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A container, because it belongs to the message above it. Without one it
            // reads as having fallen out of the bubble rather than following from it.
            .background(Tokens.surface,
                        in: RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
            .task {
                guard !reduceMotion else { drawn = 1; return }
                withAnimation(.easeOut(duration: 1.1)) { drawn = 1 }
            }
        }
    }

    private func header(_ summary: BaselineSummary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(kind.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Tokens.textSecondary)
            Spacer(minLength: 8)
            Text(summary.mean.formatted(.number.precision(.fractionLength(precision))))
                .font(.system(size: 22, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
            Text(kind.unit)
                .font(.system(size: 12))
                .foregroundStyle(Tokens.textSecondary)
        }
    }

    /// Says what the picture means, in the same register as every other chart in the
    /// app: the fact, not a description of the drawing.
    private func footer(_ summary: BaselineSummary, latest: Double) -> some View {
        Text(summary.contains(latest)
             ? "Your usual range, from \(summary.count) days. Today sits inside it."
             : "Your usual range, from \(summary.count) days. Today sits outside it.")
            .font(.system(size: 13))
            .foregroundStyle(Tokens.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var precision: Int { kind == .bloodOxygen || kind == .hrv ? 1 : 0 }

    private func draw(_ context: GraphicsContext, size: CGSize,
                      summary: BaselineSummary, latest: Double) {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 8)
        let usable = values.filter(\.isFinite)
        guard rect.width > 20, usable.count > 1 else { return }

        // Scale to the readings themselves with a little air, so the band is never
        // flush against an edge and the shape of the spread is legible.
        let low = min(usable.min() ?? 0, summary.low)
        let high = max(usable.max() ?? 1, summary.high)
        let span = max(high - low, 0.0001)
        let pad = span * 0.12
        func y(_ value: Double) -> CGFloat {
            rect.maxY - rect.height * (value - low + pad) / (span + pad * 2)
        }

        // The band first, behind everything, soft at its edges because "roughly this"
        // is the honest claim.
        let bandTop = y(summary.high), bandBottom = y(summary.low)
        let band = CGRect(x: rect.minX, y: bandTop, width: rect.width, height: bandBottom - bandTop)
        context.fill(
            Path(roundedRect: band, cornerRadius: min(band.height / 2, 18), style: .continuous),
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: Tokens.accent.opacity(0), location: 0),
                    .init(color: Tokens.accent.opacity(0.16), location: 0.5),
                    .init(color: Tokens.accent.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: band.midX, y: band.minY),
                endPoint: CGPoint(x: band.midX, y: band.maxY)))

        // The middle of it.
        var middle = Path()
        middle.move(to: CGPoint(x: rect.minX, y: y(summary.mean)))
        middle.addLine(to: CGPoint(x: rect.maxX, y: y(summary.mean)))
        context.stroke(middle, with: .color(Tokens.accent.opacity(0.42)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round))

        // Every reading, oldest to newest, appearing left to right as it draws.
        let step = rect.width / CGFloat(max(usable.count - 1, 1))
        for (index, value) in usable.enumerated() {
            let progress = Double(index) / Double(max(usable.count - 1, 1))
            guard progress <= drawn else { break }
            let isLast = index == usable.count - 1
            guard !isLast else { continue }
            let point = CGPoint(x: rect.minX + step * CGFloat(index), y: y(value))
            let radius: CGFloat = summary.contains(value) ? 2.2 : 1.8
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(Tokens.textSecondary.opacity(summary.contains(value) ? 0.42 : 0.22)))
        }

        // Today, once the rest has arrived.
        guard drawn >= 0.98 else { return }
        let point = CGPoint(x: rect.maxX, y: y(latest))
        for (radius, alpha) in [(10.0, 0.10), (7.0, 0.14)] {
            context.fill(Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                                width: radius * 2, height: radius * 2)),
                         with: .color(Tokens.accent.opacity(alpha)))
        }
        context.fill(Path(ellipseIn: CGRect(x: point.x - 4.5, y: point.y - 4.5,
                                            width: 9, height: 9)),
                     with: .color(Tokens.accent))
    }
}
