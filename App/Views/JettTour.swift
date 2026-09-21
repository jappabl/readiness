import SwiftUI

/// Jett coming up off the tab bar to say something, and settling into the card he
/// already lives in.
///
/// Two moments, one mechanism. Every morning he flies up and gives the day's call, then
/// lands in the coaching card under the rings, which is exactly where his face already
/// sits: the animation resolves into the screen rather than leaving it. The first time
/// the numbers are real he takes the long way round, stopping at each ring to say what
/// it is, because Hao's friend opened the app and did not know what strain meant and no
/// sentence in the app would have told him.
///
/// He is a rigged character who blinks and breathes on his own, and `isSpeaking` moves
/// his mouth, so a stop reads as somebody talking rather than a label appearing. That is
/// the whole reason this is worth doing instead of a tooltip.
///
/// An element offers itself with `.explains(...)`, which publishes its frame. Nothing
/// else needs to know this exists, and a card that is absent today simply has no beat.

/// One thing he says, and where he says it.
struct JettBeat: Equatable, Identifiable {
    /// The id of the element he flies to. Nil parks him mid-screen.
    let anchor: String?
    let text: String
    var id: String { (anchor ?? "centre") + text }
}

struct TourAnchors: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Offers this view as somewhere Jett can fly to.
    func explains(_ id: String) -> some View {
        anchorPreference(key: TourAnchors.self, value: .bounds) { [id: $0] }
    }
}

/// What he has already said, so he does not say it twice.
enum JettMoments {
    private static let walkthroughKey = "jett.walkthrough.given"
    private static let greetedKey = "jett.greeted.day"

    static var hasWalkedThrough: Bool {
        UserDefaults.standard.bool(forKey: walkthroughKey)
    }
    static func markWalkedThrough() {
        UserDefaults.standard.set(true, forKey: walkthroughKey)
    }

    /// One greeting a day, on the calendar's terms rather than a timer, so a night
    /// shift still gets one morning.
    static func hasGreeted(on day: Date, calendar: Calendar = .current) -> Bool {
        guard let last = UserDefaults.standard.object(forKey: greetedKey) as? Date
        else { return false }
        return calendar.isDate(last, inSameDayAs: day)
    }
    static func markGreeted(on day: Date) {
        UserDefaults.standard.set(day, forKey: greetedKey)
    }

    static func forgetEverything() {
        UserDefaults.standard.removeObject(forKey: walkthroughKey)
        UserDefaults.standard.removeObject(forKey: greetedKey)
    }
}

/// A speech bubble with a tail pointing back at whoever is talking.
private struct SpeechBubble: Shape {
    /// Where along the top edge the tail sits, 0 to 1.
    var tail: CGFloat
    var radius: CGFloat = 18

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        let x = rect.minX + max(radius + 10, min(rect.width - radius - 10, rect.width * tail))
        path.move(to: CGPoint(x: x - 10, y: rect.minY + 2))
        path.addLine(to: CGPoint(x: x + 2, y: rect.minY - 12))
        path.addLine(to: CGPoint(x: x + 12, y: rect.minY + 2))
        path.closeSubpath()
        return path
    }
}

/// Him, flying.
struct JettFlight: View {
    let beats: [JettBeat]
    let frames: [String: CGRect]
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var landed = false
    @State private var visible = false

    private var beat: JettBeat? { index < beats.count ? beats[index] : nil }
    private var target: CGRect? { beat?.anchor.flatMap { frames[$0] } }

    private static let headSize: CGFloat = 46
    private static let seatedSize: CGFloat = 24

    /// His seat in the tab bar, which is where he comes from.
    private func home(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height - 46)
    }

    /// Where his head goes.
    ///
    /// Deliberately not the same geometry every time. Three stops dead centre under
    /// three rings is a table of contents rather than somebody moving around a screen,
    /// so he takes the near corner of whatever he is talking about, alternates which
    /// side, and varies the drop by a few points a stop.
    private func headPoint(in size: CGSize) -> CGPoint {
        if landed { return home(in: size) }
        // Nothing to stand beside: the day's call is about the day, not about a card.
        guard let target else { return CGPoint(x: size.width / 2 - 40, y: size.height * 0.3) }
        let leaning: CGFloat = index.isMultiple(of: 2) ? -1 : 1
        let x = target.midX + leaning * min(target.width / 2, 34)
        let drop: CGFloat = [30, 42, 34, 38][index % 4]
        let above = target.maxY + 150 > size.height
        return CGPoint(x: min(max(34, x), size.width - 34),
                       y: above ? target.minY - drop : target.maxY + drop)
    }

    /// A slight lean, so he reads as arriving rather than being placed.
    private var tilt: Double {
        guard !reduceMotion, !landed else { return 0 }
        return [-5.0, 4.0, -3.0, 6.0][index % 4]
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let head = headPoint(in: size)
            ZStack(alignment: .topLeading) {
                scrim
                if let beat, !landed {
                    bubble(beat, head: head, in: size)
                }
                JettRive(size: Self.headSize, isSpeaking: !landed)
                    .rotationEffect(.degrees(tilt))
                    .shadow(color: .black.opacity(landed ? 0 : 0.28), radius: 16, x: 0, y: 7)
                    .position(head)
                    .opacity(landed ? 0 : 1)
            }
            .animation(flight, value: index)
            .animation(flight, value: landed)
            .opacity(visible ? 1 : 0)
            .contentShape(Rectangle())
            // The whole screen advances him. A button to press would be one more thing
            // to explain during the explanation.
            .onTapGesture { advance() }
            .onAppear { withAnimation(.easeOut(duration: 0.3)) { visible = true } }
        }
        // Deliberately not ignoring the safe area: the frames come from the overlay's
        // own coordinate space, and a view that ignores it while reading frames that do
        // not is offset by the whole header. He landed on top of the ring he was
        // explaining rather than under it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(beat.map { "Jett says: \($0.text). Tap to continue." } ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { advance() }
    }

    private var flight: Animation? {
        reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.72)
    }

    /// Dark everywhere except the thing he is talking about.
    ///
    /// Light enough to read the page through. The point is where he is, not the scrim,
    /// and a heavy one turns this into a product tour.
    private var scrim: some View {
        Rectangle()
            .fill(.black.opacity(0.3))
            .mask {
                Rectangle()
                    .overlay {
                        if let target {
                            RoundedRectangle(cornerRadius: Tokens.cardRadius + 4,
                                             style: .continuous)
                                .frame(width: target.width + 14, height: target.height + 14)
                                .position(x: target.midX, y: target.midY)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }

    /// What he is saying, hanging off his head.
    private func bubble(_ beat: JettBeat, head: CGPoint, in size: CGSize) -> some View {
        let margin = Tokens.screenMargin
        let width = size.width - margin * 2
        return Text(beat.text)
            .font(.system(size: 15))
            .foregroundStyle(Tokens.textPrimary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width - 28, alignment: .leading)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background {
                SpeechBubble(tail: (head.x - margin) / width)
                    .fill(Tokens.surface)
                    .shadow(color: .black.opacity(0.22), radius: 20, x: 0, y: 8)
            }
            .position(x: size.width / 2, y: head.y + Self.headSize / 2 + 40)
            .transition(.opacity)
            .id(beat.id)
    }

    private func advance() {
        if index + 1 < beats.count {
            Haptics.light()
            index += 1
        } else {
            // Home, which is his seat in the tab bar. He arrived from there, so that is
            // where the moment ends rather than him blinking out mid-air.
            Haptics.decided()
            landed = true
            withAnimation(.easeIn(duration: 0.3).delay(0.3)) { visible = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { onFinish() }
        }
    }
}
