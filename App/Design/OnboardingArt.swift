import SwiftUI

// Three pieces of motion that carry what used to be body copy. Drawn rather than
// imported: they are made of the same primitives as the rest of the app, so they pick
// up the palette, dark mode and Dynamic Type for free, and a colour is never a hex
// value transcribed twice.
//
// All three run off `TimelineView(.animation)` with the phase computed from the
// timeline's own clock. Nothing is written to state per frame, and honouring Reduce
// Motion is a matter of pinning the phase to its settled value.

// MARK: - Shared

private func clamp01(_ value: Double) -> Double { min(1, max(0, value)) }

/// Ease out cubic. Everything here decelerates into place; nothing overshoots.
private func settle(_ t: Double) -> Double { 1 - pow(1 - clamp01(t), 3) }

/// Eases in and out, for motion that starts and ends at rest.
private func breathe(_ t: Double) -> Double {
    let t = clamp01(t)
    return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}

/// A window inside the loop, as a 0-1 fraction of its own span.
private func stage(_ t: Double, _ from: Double, _ to: Double) -> Double {
    guard to > from else { return t >= to ? 1 : 0 }
    return clamp01((t - from) / (to - from))
}

/// Deterministic noise. The picture has to be identical every time it plays, so there
/// is no randomness at runtime, only an arithmetic sequence that looks like some.
///
/// The sample is centred and scaled after it is generated rather than trusted raw. An
/// earlier version took bits straight off a plain LCG, whose consecutive draws were
/// correlated enough to land the sample's mean at 0.62 — so the cloud of nights sat
/// visibly below the band that was supposed to describe it, and the picture quietly
/// contradicted the sentence under it.
private func scatter(count: Int, seed: UInt64) -> [Double] {
    var state = seed

    // SplitMix64, which mixes well enough that three draws in a row are independent.
    func next() -> Double {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        return Double(z >> 40) / Double(0xFF_FFFF)
    }

    let raw: [Double] = (0..<count).map { _ in
        let a = next(), b = next(), c = next()
        // Three uniforms averaged make a visible hump rather than a smear.
        return (a + b + c) / 3
    }

    let mean = raw.reduce(0, +) / Double(count)
    let variance = raw.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(count)
    let sd = variance.squareRoot()
    guard sd > 0 else { return Array(repeating: 0.5, count: count) }

    // One standard deviation lands at 0.24 either side of the middle, which is the
    // half-height the band settles to. Two thirds of the nights end up inside it, and
    // none of them pile up against the top or bottom edge.
    return raw.map { clamp01(0.5 + ($0 - mean) / sd * 0.24) }
}

// MARK: - Baseline

/// What "measured against you" means, without saying it.
///
/// Past nights fall in as grey dots, a band tightens around the middle of them as the
/// evidence accumulates, and today lands inside it. There is deliberately no second
/// population anywhere in the frame: the whole point is that there is nothing to
/// compare against except the dots already on screen.
struct BaselineArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The accent is a bright green, and a translucent wash of it over the dark canvas
    /// glows in a way it never does over the light one. The band is dimmer at night.
    @Environment(\.colorScheme) private var scheme

    private static let loop: Double = 7.4
    private static let nights = scatter(count: 34, seed: 0x9E37_79B9_7F4A_7C15)
    /// Today sits just inside the band. Not in the middle: it has to look like a
    /// reading rather than a target.
    private static let today: Double = 0.585

    var body: some View {
        TimelineView(.animation) { context in
            Canvas { ctx, size in
                draw(ctx, size: size, t: phase(context.date))
            }
        }
        .frame(height: 292)
        .accessibilityHidden(true)
    }

    private func phase(_ date: Date) -> Double {
        guard !reduceMotion else { return 0.90 }
        let elapsed = date.timeIntervalSinceReferenceDate
        return (elapsed.truncatingRemainder(dividingBy: Self.loop)) / Self.loop
    }

    private func draw(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: 10, dy: 14)
        guard rect.width > 40, rect.height > 40 else { return }

        let mean = rect.midY
        let spread = rect.height * 0.42

        let axis = settle(stage(t, 0, 0.12))
        let bandIn = stage(t, 0.14, 0.24)
        let tighten = settle(stage(t, 0.16, 0.46))
        let todayIn = settle(stage(t, 0.48, 0.58))
        let pulse = stage(t, 0.56, 0.76)
        // The loop closes by fading, never by cutting.
        let out = 1 - stage(t, 0.955, 1.0)

        var ctx = ctx
        ctx.opacity = out

        // Ends holding about two thirds of the nights, which is what a normal range
        // is. A band that contains everything says nothing.
        let half = spread * (1.02 - 0.54 * tighten)
        drawBand(ctx, rect: rect, mean: mean, half: half, opacity: bandIn,
                 dark: scheme == .dark)
        drawMeanLine(ctx, rect: rect, y: mean, reach: axis, opacity: bandIn)
        drawAxis(ctx, rect: rect, t: t)
        drawNights(ctx, rect: rect, mean: mean, spread: spread, t: t,
                   settledHalf: spread * 0.48)
        drawToday(ctx, rect: rect, mean: mean, spread: spread,
                  arrival: todayIn, pulse: pulse)
    }

    /// A soft channel rather than a boxed range: edges that fade read as "roughly
    /// this", which is the honest claim.
    private func drawBand(_ ctx: GraphicsContext, rect: CGRect, mean: CGFloat,
                          half: CGFloat, opacity: Double, dark: Bool) {
        guard opacity > 0 else { return }
        let fill = (dark ? 0.085 : 0.16) * opacity
        let edgeAlpha = (dark ? 0.26 : 0.30) * opacity
        let band = CGRect(x: rect.minX, y: mean - half,
                          width: rect.width, height: half * 2)
        let shape = Path(roundedRect: band, cornerRadius: min(half, 26), style: .continuous)
        ctx.fill(shape, with: .linearGradient(
            Gradient(stops: [
                .init(color: Tokens.accent.opacity(0), location: 0),
                .init(color: Tokens.accent.opacity(fill), location: 0.5),
                .init(color: Tokens.accent.opacity(0), location: 1),
            ]),
            startPoint: CGPoint(x: band.midX, y: band.minY),
            endPoint: CGPoint(x: band.midX, y: band.maxY)))

        for y in [band.minY, band.maxY] {
            var edge = Path()
            edge.move(to: CGPoint(x: rect.minX, y: y))
            edge.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(edge, with: .linearGradient(
                Gradient(stops: [
                    .init(color: Tokens.accent.opacity(0), location: 0),
                    .init(color: Tokens.accent.opacity(edgeAlpha), location: 0.5),
                    .init(color: Tokens.accent.opacity(0), location: 1),
                ]),
                startPoint: CGPoint(x: rect.minX, y: y),
                endPoint: CGPoint(x: rect.maxX, y: y)),
                style: StrokeStyle(lineWidth: 0.75))
        }
    }

    private func drawMeanLine(_ ctx: GraphicsContext, rect: CGRect,
                              y: CGFloat, reach: Double, opacity: Double) {
        guard reach > 0 else { return }
        var line = Path()
        line.move(to: CGPoint(x: rect.minX, y: y))
        line.addLine(to: CGPoint(x: rect.minX + rect.width * reach, y: y))
        ctx.stroke(line, with: .linearGradient(
            Gradient(stops: [
                .init(color: Tokens.accent.opacity(0), location: 0),
                .init(color: Tokens.accent.opacity(0.40 * max(opacity, 0.35)), location: 0.35),
                .init(color: Tokens.accent.opacity(0.40 * max(opacity, 0.35)), location: 0.65),
                .init(color: Tokens.accent.opacity(0), location: 1),
            ]),
            startPoint: CGPoint(x: rect.minX, y: y),
            endPoint: CGPoint(x: rect.maxX, y: y)),
            style: StrokeStyle(lineWidth: 1, lineCap: .round))
    }

    /// Ticks under the cloud. Without them the dots float; with them they are nights,
    /// in order, and the picture is a record rather than a texture.
    private func drawAxis(_ ctx: GraphicsContext, rect: CGRect, t: Double) {
        let count = Self.nights.count
        let field = rect.width * 0.80
        let y = rect.maxY - 4

        for index in stride(from: 0, to: count, by: 4) {
            let begins = 0.04 + 0.32 * Double(index) / Double(count - 1)
            let local = settle(stage(t, begins, begins + 0.09))
            guard local > 0 else { continue }
            let x = rect.minX + field * Double(index) / Double(count - 1)
            var tick = Path()
            tick.move(to: CGPoint(x: x, y: y - 5))
            tick.addLine(to: CGPoint(x: x, y: y))
            ctx.stroke(tick, with: .color(Tokens.textSecondary.opacity(0.30 * local)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
    }

    private func drawNights(_ ctx: GraphicsContext, rect: CGRect, mean: CGFloat,
                            spread: CGFloat, t: Double, settledHalf: CGFloat) {
        let count = Self.nights.count
        // Stops short of the right edge so today's reading has somewhere to land.
        let field = rect.width * 0.80

        for (index, value) in Self.nights.enumerated() {
            let begins = 0.04 + 0.32 * Double(index) / Double(count - 1)
            let local = settle(stage(t, begins, begins + 0.09))
            guard local > 0 else { continue }

            let x = rect.minX + field * Double(index) / Double(count - 1)
            let y = mean + (value - 0.5) * spread * 2
            // Drops the last few points into place rather than appearing at rest.
            let dy = (1 - local) * 9

            let inside = abs(y - mean) <= settledHalf
            // Recent nights carry more weight in the baseline, so they carry more ink.
            let recency = 0.66 + 0.34 * Double(index) / Double(count - 1)
            let alpha = (inside ? 0.62 : 0.34) * recency * local
            let r: CGFloat = inside ? 3.2 : 2.7
            let dot = CGRect(x: x - r, y: y - r + dy, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: dot), with: .color(Tokens.textSecondary.opacity(alpha)))
        }
    }

    private func drawToday(_ ctx: GraphicsContext, rect: CGRect, mean: CGFloat,
                           spread: CGFloat, arrival: Double, pulse: Double) {
        guard arrival > 0 else { return }
        let x = rect.maxX - 16
        let resting = mean + (Self.today - 0.5) * spread * 2
        let y = resting - (1 - arrival) * 30

        // One expanding ring, once. Anything more turns a reading into a notification.
        if pulse > 0, pulse < 1 {
            let radius = 7 + 26 * settle(pulse)
            let ring = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            ctx.stroke(Path(ellipseIn: ring),
                       with: .color(Tokens.accent.opacity(0.34 * (1 - pulse))),
                       style: StrokeStyle(lineWidth: 1.2))
        }

        for (radius, alpha) in [(11.0, 0.10), (8.0, 0.14)] {
            let halo = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            ctx.fill(Path(ellipseIn: halo),
                     with: .color(Tokens.accent.opacity(alpha * arrival)))
        }
        let r: CGFloat = 5.2
        let dot = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: dot), with: .color(Tokens.accent.opacity(arrival)))
    }
}

// MARK: - Nothing leaves

/// What is read comes in, and nothing goes back out.
///
/// Three streams arrive and settle inside an outline, a line closes around them, and
/// then one of them tries the wall and stays put. No padlock and no shield: those read
/// as a security vendor's stock art, and the dot that cannot get out is the whole idea.
struct PrivateArt: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private static let loop: Double = 7.8

    /// The three sources, named on screen. An earlier version had an unlabelled box
    /// with dots arriving from nowhere in particular, and needed a row of chips under
    /// it to explain itself; naming the sources in the picture retired the chips.
    private static let sources: [(symbol: String, tint: Color)] = [
        ("moon.zzz", Tokens.sleepLow),
        ("heart", Tokens.recoveryHigh),
        ("flame", Tokens.strainLow),
    ]

    private static let badge: CGFloat = 36
    private static let lane: CGFloat = 78          // vertical gap between sources
    private static let inset: CGFloat = 14         // from the leading edge

    var body: some View {
        ZStack(alignment: .leading) {
            TimelineView(.animation) { context in
                Canvas { ctx, size in
                    draw(ctx, size: size, t: phase(context.date))
                }
            }
            VStack(spacing: Self.lane - Self.badge) {
                ForEach(Self.sources.indices, id: \.self) { index in
                    let source = Self.sources[index]
                    Image(systemName: source.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(source.tint)
                        .frame(width: Self.badge, height: Self.badge)
                        .background(Tokens.surface, in: Circle())
                        .overlay(Circle().strokeBorder(source.tint.opacity(0.35), lineWidth: 1))
                }
            }
            .padding(.leading, Self.inset)
        }
        .frame(height: 296)
        .accessibilityHidden(true)
    }

    private func phase(_ date: Date) -> Double {
        guard !reduceMotion else { return 0.88 }
        let elapsed = date.timeIntervalSinceReferenceDate
        return (elapsed.truncatingRemainder(dividingBy: Self.loop)) / Self.loop
    }

    /// Where each arriving dot comes to rest, as offsets from the centre. Grouped into
    /// three rows by source, so what lands stays recognisably what arrived.
    private static let berths: [CGPoint] = [
        CGPoint(x: -16, y: -62), CGPoint(x: 2, y: -62), CGPoint(x: 20, y: -62),
        CGPoint(x: -16, y: 0),   CGPoint(x: 2, y: 0),   CGPoint(x: 20, y: 0),
        CGPoint(x: -16, y: 62),  CGPoint(x: 2, y: 62),  CGPoint(x: 20, y: 62),
    ]

    private func draw(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        // The phone sits in the space left of the source badges rather than dead
        // centre, so the whole picture reads left to right.
        let centre = CGPoint(x: size.width * 0.66, y: size.height / 2)
        let body = CGRect(x: centre.x - 52, y: centre.y - 92, width: 104, height: 184)
        let outline = Path(roundedRect: body, cornerRadius: 22, style: .continuous)

        let drawn = settle(stage(t, 0, 0.09))
        let sealing = settle(stage(t, 0.32, 0.46))
        let out = 1 - stage(t, 0.955, 1.0)

        var ctx = ctx
        ctx.opacity = out

        let ink = Tokens.textSecondary.opacity(scheme == .dark ? 0.46 : 0.32)
        ctx.stroke(outline.trimmedPath(from: 0, to: drawn), with: .color(ink),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

        // A speaker slot and a home bar, which is all it takes for a rounded rectangle
        // to become a phone.
        if drawn >= 1 {
            let slot = CGRect(x: centre.x - 11, y: body.minY + 10, width: 22, height: 3)
            ctx.fill(Path(roundedRect: slot, cornerRadius: 1.5), with: .color(ink))
            let bar = CGRect(x: centre.x - 17, y: body.maxY - 12, width: 34, height: 3)
            ctx.fill(Path(roundedRect: bar, cornerRadius: 1.5), with: .color(ink))
        }

        drawStreams(ctx, size: size, centre: centre, t: t)

        if sealing > 0 {
            ctx.stroke(outline.trimmedPath(from: 0, to: sealing),
                       with: .color(Tokens.accent.opacity(0.85)),
                       style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
        if sealing >= 1 {
            drawRefusal(ctx, centre: centre, body: body, outline: outline, t: t)
        }
    }

    /// Each source leaves its badge on a lane of its own.
    private func lane(_ size: CGSize, _ index: Int) -> CGPoint {
        CGPoint(x: Self.inset + Self.badge,
                y: size.height / 2 + Self.lane * CGFloat(index - 1))
    }

    private func drawStreams(_ ctx: GraphicsContext, size: CGSize,
                             centre: CGPoint, t: Double) {
        for index in 0..<Self.berths.count {
            let stream = index / 3
            let start = lane(size, stream)
            let berth = Self.berths[index]
            let end = CGPoint(x: centre.x + berth.x, y: centre.y + berth.y)
            let control = CGPoint(x: (start.x + end.x) / 2, y: start.y)
            let tint = Self.sources[stream].tint

            // The lane itself, drawn once per stream behind the dots on it.
            if index % 3 == 0 {
                var rail = Path()
                rail.move(to: start)
                rail.addQuadCurve(to: CGPoint(x: centre.x + 24, y: end.y), control: control)
                ctx.stroke(rail, with: .color(tint.opacity(0.16)),
                           style: StrokeStyle(lineWidth: 1))
            }

            let begins = 0.06 + 0.03 * Double(index)
            let travel = breathe(stage(t, begins, begins + 0.20))
            guard travel > 0 else { continue }

            let p = bezier(start, control, end, travel)
            let r: CGFloat = 3.4
            let glow: CGFloat = travel < 1 ? 9 : 7
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - glow, y: p.y - glow,
                                            width: glow * 2, height: glow * 2)),
                     with: .radialGradient(
                        Gradient(colors: [tint.opacity(0.20), tint.opacity(0)]),
                        center: p, startRadius: 0, endRadius: glow))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r,
                                            width: r * 2, height: r * 2)),
                     with: .color(tint))
        }
    }

    /// The beat the whole thing exists for: something inside moves at the wall, the
    /// wall answers, and it stays in.
    private func drawRefusal(_ ctx: GraphicsContext, centre: CGPoint,
                             body: CGRect, outline: Path, t: Double) {
        let attempt = stage(t, 0.52, 0.72)
        guard attempt > 0, attempt < 1 else { return }
        let reach = sin(attempt * .pi)
        let berth = Self.berths[5]
        let from = CGPoint(x: centre.x + berth.x, y: centre.y + berth.y)
        let wall = CGPoint(x: body.maxX - 8, y: from.y)
        let p = CGPoint(x: from.x + (wall.x - from.x) * reach, y: from.y)

        let contact = max(0, (reach - 0.82) / 0.18)
        if contact > 0 {
            let radius: CGFloat = 14
            ctx.fill(Path(ellipseIn: CGRect(x: wall.x - radius, y: wall.y - radius,
                                            width: radius * 2, height: radius * 2)),
                     with: .radialGradient(
                        Gradient(colors: [Tokens.accent.opacity(0.32 * contact),
                                          Tokens.accent.opacity(0)]),
                        center: wall, startRadius: 0, endRadius: radius))
            ctx.stroke(outline, with: .color(Tokens.accent.opacity(0.35 * contact)),
                       style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
        }

        let r: CGFloat = 3.4
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r,
                                        width: r * 2, height: r * 2)),
                 with: .color(Tokens.recoveryHigh))
    }

    private func bezier(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ u: Double) -> CGPoint {
        let inv = 1 - u
        return CGPoint(x: inv * inv * a.x + 2 * inv * u * b.x + u * u * c.x,
                       y: inv * inv * a.y + 2 * inv * u * b.y + u * u * c.y)
    }
}

// MARK: - Reading

/// Jett, mid-read, with the day's three measures sweeping around him.
///
/// The arcs are the home screen's rings taken apart: same three meanings, same
/// light-to-deep sweep, so the loading state is made of the thing being loaded. They
/// never complete and reset, because a ring that fills is a progress bar and this has
/// no percentage to report.
struct ReadingArt: View {
    var size: CGFloat = 214

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Arc {
        /// Radius in points against a 214pt box. Must clear Jett's own circle, which
        /// is 84pt across; anything smaller is drawn and then hidden by his face.
        let radius: CGFloat
        let sweep: Double       // degrees
        let turns: Double       // revolutions per second, signed
        let offset: Double      // starting degrees
        let tint: Color
    }

    private static let arcs: [Arc] = [
        Arc(radius: 88, sweep: 92, turns: 0.19, offset: 0, tint: Tokens.strainDeep),
        Arc(radius: 74, sweep: 124, turns: -0.14, offset: 140, tint: Tokens.recoveryDeep),
        Arc(radius: 60, sweep: 76, turns: 0.26, offset: 250, tint: Tokens.sleepDeep),
    ]

    var body: some View {
        ZStack {
            TimelineView(.animation) { context in
                Canvas { ctx, size in
                    draw(ctx, size: size, elapsed: clock(context.date))
                }
                .frame(width: size, height: size)
            }
            JettRive(size: 84, isThinking: true)
        }
        .frame(width: size, height: size)
    }

    private func clock(_ date: Date) -> Double {
        reduceMotion ? 0 : date.timeIntervalSinceReferenceDate
    }

    /// Each arc is drawn as short segments whose alpha ramps from nothing at the tail
    /// to full at the head.
    ///
    /// A conic gradient would be one call, but its zero angle and the arc's start angle
    /// are not the same convention, which put the transparent end of the ramp straight
    /// over the visible sweep. Segments have no convention to get wrong, and the cost
    /// is a few dozen strokes a frame.
    private func draw(_ ctx: GraphicsContext, size: CGSize, elapsed: Double) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let scale = min(size.width, size.height) / 214
        let steps = 34

        for arc in Self.arcs {
            let radius = arc.radius * scale
            let head = arc.offset + elapsed * arc.turns * 360
            let step = arc.sweep / Double(steps)

            for index in 0..<steps {
                // Index 0 is the tail. Squared so the bright part stays near the head
                // rather than smearing along the whole sweep.
                let along = Double(index) / Double(steps - 1)
                let alpha = 0.08 + 0.92 * pow(along, 1.6)

                // Overlapped and round-capped at both ends: butt caps left visible
                // steps down the tail, which made a smooth sweep look like a dashed one.
                let from = Angle(degrees: head - arc.sweep + step * Double(index) - step)
                let to = Angle(degrees: head - arc.sweep + step * Double(index + 1))

                var path = Path()
                path.addArc(center: centre, radius: radius,
                            startAngle: from, endAngle: to, clockwise: false)
                ctx.stroke(path, with: .color(arc.tint.opacity(alpha)),
                           style: StrokeStyle(lineWidth: 3.6 * scale, lineCap: .round))
            }
        }
    }
}
