import SwiftUI
import UIKit

/// What a share card says: the day's three scores, which one leads, and the day's call.
///
/// Scores and the call only. No heart rate variability, no resting heart rate, no sleep
/// stages in hours: people share these without thinking, and a readable physiology
/// profile on somebody's story is not something the app should hand them by default.
struct ShareCardData: Equatable {
    let date: Date
    let hero: Signal
    let strain: Int?
    let recovery: Int?
    let sleep: Int?
    /// "Maintain", and the sentence under it. Only for today: a call is advice for the
    /// day it was made, and a card from last Tuesday repeating it reads as advice now.
    let headline: String?
    let call: String?

    func percent(_ signal: Signal) -> Int? {
        switch signal {
        case .strain: return strain
        case .recovery: return recovery
        case .sleep: return sleep
        }
    }

    /// The two that sit under the hero, in the order Today shows them.
    var others: [Signal] { [Signal.strain, .recovery, .sleep].filter { $0 != hero } }

    /// A card with nothing in the middle is not worth sending anybody.
    var isShareable: Bool { percent(hero) != nil }
}

/// The card itself, drawn at 360 by 640 points and rendered at three times that, which
/// is 1080 by 1920: the size a story wants, so nothing gets cropped or scaled.
///
/// Built from the app's own parts (the signal's sky, `RingGauge`, `JettFace`, the type
/// scale) rather than a look of its own, so a card on somebody's story is recognisably
/// the screen they took it from, only calmer.
struct ShareCardView: View {
    let data: ShareCardData

    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack(alignment: .top) {
            Tokens.canvas
            LinearGradient(stops: [
                .init(color: data.hero.sky[0], location: 0.00),
                .init(color: data.hero.sky[1], location: 0.40),
                .init(color: data.hero.sky[2], location: 0.70),
                .init(color: Tokens.canvas, location: 1.00),
            ], startPoint: .top, endPoint: .bottom)
            // Wider than the card before the blur, so the blur has colour to pull in
            // at the edges instead of fading the corners to pale.
            .frame(width: Self.size.width + 96, height: 430)
            .blur(radius: 24)

            VStack(spacing: 0) {
                Text(data.date, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.system(size: 12, weight: .medium))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(Tokens.textSecondary)
                    .padding(.top, 46)

                heroRing
                    .padding(.top, 30)

                // A label, not a heading: the number above and the call below are the
                // two things worth reading, and this only says which number it is.
                Text(data.hero.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tokens.textSecondary)
                    .padding(.top, 14)

                if let headline = data.headline {
                    VStack(spacing: 6) {
                        Text(headline)
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Tokens.textPrimary)
                        if let call = data.call {
                            Text(call)
                                .font(.system(size: 15))
                                .foregroundStyle(Tokens.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.top, 22)
                }

                Spacer(minLength: 20)

                HStack(spacing: 48) {
                    ForEach(data.others, id: \.self) { signal in
                        VStack(spacing: 8) {
                            RingGauge(signal: signal, percent: data.percent(signal),
                                      lineWidth: 7, figureSize: 17, animates: false)
                                .frame(width: 62, height: 62)
                            Text(signal.title)
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.textSecondary)
                        }
                    }
                }

                Spacer(minLength: 20)

                signature
                    .padding(.bottom, 40)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
    }

    /// The hero on the same raised disc as the detail screen's.
    private var heroRing: some View {
        ZStack {
            Circle()
                .fill(Tokens.surface)
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 6)
            RingGauge(signal: data.hero, percent: data.percent(data.hero),
                      lineWidth: 14, figureSize: 48, animates: false)
                .padding(18)
        }
        .frame(width: 192, height: 192)
    }

    /// Who it is from, quietly. The address is the only way a stranger can find the app
    /// from a story, so it is there, and small.
    private var signature: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                JettFace(size: 24)
                Text("Coach Jett")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
            }
            Text("coachjett.com")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.textTertiary)
        }
    }
}

@MainActor
enum ShareCardRenderer {
    /// The card as an image, in the appearance the person is looking at.
    static func image(_ data: ShareCardData, colorScheme: ColorScheme) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(data: data)
            .environment(\.colorScheme, colorScheme))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// The card, and one way out of here with it.
struct ShareCardSheet: View {
    let data: ShareCardData
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?

    var body: some View {
        VStack(spacing: 20) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Color.clear.aspectRatio(ShareCardView.size, contentMode: .fit)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Tokens.hairline, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
            .frame(maxHeight: .infinity)

            if let image {
                ShareLink(item: Image(uiImage: image),
                          preview: SharePreview("Coach Jett", image: Image(uiImage: image))) {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                        Text("Share").font(.body.weight(.semibold))
                    }
                    .foregroundStyle(Tokens.onAction)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Tokens.action,
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 4)
                }
                .simultaneousGesture(TapGesture().onEnded { Haptics.light() })
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .background(Tokens.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: colorScheme) { image = ShareCardRenderer.image(data, colorScheme: colorScheme) }
    }
}

/// The share mark for a screen's corner.
struct ShareCardButton: View {
    let action: () -> Void

    var body: some View {
        Button { Haptics.light(); action() } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Tokens.textPrimary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share today")
    }
}

/// When somebody screenshots a screen that has a card, a small offer of the clean
/// version. Their screenshot is theirs and is not touched; this sits on top for a few
/// seconds and leaves.
struct ScreenshotShareOffer: ViewModifier {
    let isEnabled: Bool
    let onAccept: () -> Void

    @State private var visible = false
    @State private var onScreen = false
    @State private var hideTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if visible {
                    Button {
                        Haptics.light()
                        hide()
                        onAccept()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Share a clean one")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(Tokens.textPrimary)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity
                                : .move(edge: .top).combined(with: .opacity))
                }
            }
            .onAppear { onScreen = true }
            .onDisappear { onScreen = false; hide() }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.userDidTakeScreenshotNotification)) { _ in
                guard isEnabled, onScreen else { return }
                show()
            }
    }

    private func show() {
        hideTask?.cancel()
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.35)) {
            visible = true
        }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    private func hide() {
        hideTask?.cancel()
        hideTask = nil
        withAnimation(.easeOut(duration: 0.2)) { visible = false }
    }
}

extension View {
    func offersShareCardOnScreenshot(_ isEnabled: Bool, onAccept: @escaping () -> Void) -> some View {
        modifier(ScreenshotShareOffer(isEnabled: isEnabled, onAccept: onAccept))
    }
}
