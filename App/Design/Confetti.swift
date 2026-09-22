import SwiftUI

/// The one moment in this app that is allowed to celebrate.
///
/// Everything else here is deliberately quiet: colour carries meaning, nothing moves
/// without a reason, and a number is worth more than an adjective. This is the exception,
/// and it is an exception precisely because it happens once, to a hundred people, and
/// never again. A founding member is told in the only language that does not need a
/// sentence.
///
/// Written rather than pulled in, for one reason: it has to stop for somebody who has
/// asked their phone to stop moving things. Reduce Motion gets the message and none of
/// the movement, which is what that setting is for.
struct Confetti: View {
    var pieces: Int = 90

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var launched = false

    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat          // 0...1 of the width
        let drift: CGFloat      // how far sideways, in points
        let delay: Double
        let duration: Double
        let size: CGSize
        let spin: Double
        let tint: Color
        let circular: Bool
    }

    /// Deterministic per launch, seeded by the piece index, so nothing re-rolls when
    /// SwiftUI re-evaluates the body mid-flight and half the confetti teleports.
    private var confetti: [Piece] {
        var generator = SeededRandom(seed: 0x5EED)
        let palette: [Color] = [Tokens.accent, Tokens.strainLow, Tokens.sleepLow,
                                Tokens.recoveryLow, Tokens.textPrimary.opacity(0.55)]
        return (0..<pieces).map { index in
            Piece(id: index,
                  x: CGFloat(generator.next(in: 0.02...0.98)),
                  drift: CGFloat(generator.next(in: -60...60)),
                  delay: generator.next(in: 0...0.35),
                  duration: generator.next(in: 1.5...2.6),
                  size: CGSize(width: CGFloat(generator.next(in: 5...9)),
                               height: CGFloat(generator.next(in: 7...14))),
                  spin: generator.next(in: -520...520),
                  tint: palette[generator.index(upTo: palette.count)],
                  circular: generator.chance(0.25))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                ForEach(confetti) { piece in
                    Group {
                        if piece.circular {
                            Circle().fill(piece.tint)
                        } else {
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous).fill(piece.tint)
                        }
                    }
                    .frame(width: piece.size.width, height: piece.size.height)
                    .rotationEffect(.degrees(launched ? piece.spin : 0))
                    .offset(x: piece.x * proxy.size.width - proxy.size.width / 2
                              + (launched ? piece.drift : 0),
                            // Starts just above the top edge and falls past the bottom,
                            // so nothing pops into existence in the middle of the screen
                            // and nothing is left lying on it afterwards.
                            y: launched ? proxy.size.height + 60 : -24)
                    // No fade. Falling off the bottom is how confetti leaves, and a
                    // piece that dims on an ease-in curve is invisible for most of the
                    // time it is on screen, which is the whole of a short animation.
                    .animation(.easeIn(duration: piece.duration).delay(piece.delay),
                               value: launched)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Fires on appear, and the caller decides when that is by inserting the view.
        // It used to take a `running` flag and watch it change, which is one more thing
        // that can fail to happen: the flag flipped in the same update that created this
        // view, so there was no change left for it to observe and the confetti stayed
        // above the top of the screen for ever.
        //
        // The one-frame wait is load-bearing. Flipping the flag in `onAppear` can land in
        // the same update that first rendered this view, and an animation with no rendered
        // "before" frame is a teleport: every piece arrives at the bottom of the screen
        // instantly and nothing is ever seen falling.
        .task {
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .milliseconds(32))
            launched = true
        }
    }
}

/// Small, repeatable, and entirely local. `Double.random` re-rolls on every body
/// evaluation, which mid-animation teleports half the pieces sideways.
private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next(in range: ClosedRange<Double>) -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let unit = Double(state >> 11) / Double(UInt64.max >> 11)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    mutating func index(upTo count: Int) -> Int {
        min(count - 1, Int(next(in: 0...Double(count))))
    }

    mutating func chance(_ probability: Double) -> Bool {
        next(in: 0...1) < probability
    }
}
