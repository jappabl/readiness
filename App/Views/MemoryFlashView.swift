import SwiftUI

/// "Jett remembered that."
///
/// A memory is written without asking, because asking permission to keep a sentence
/// somebody just said would be more intrusive than keeping it. What makes that fair is
/// that they always see it happen. So this has one job and a short life: catch the eye,
/// say what was kept, and get out of the way.
///
/// The shine is the whole reason it works. A line of text that fades in at the top of a
/// screen somebody is reading gets missed; a highlight travelling across it does not,
/// and it costs nothing in space or attention afterwards.
struct MemoryFlash: View {
    let kind: AppModel.MemoryFlash.Kind
    let text: String

    @State private var shine = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        kind == .remembered ? "Jett remembered that" : "Jett dropped that"
    }

    var body: some View {
        HStack(spacing: 10) {
            // One colour for the glyph, as everywhere else. The movement carries the
            // meaning, not a tint.
            Image(systemName: kind == .remembered ? "brain.head.profile" : "eraser")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Tokens.textPrimary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Tokens.hairline, lineWidth: 0.5)
        }
        .overlay { if !reduceMotion { sheen } }
        .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
        .padding(.horizontal, Tokens.screenMargin)
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.85).delay(0.12)) { shine = 2 }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(text)")
    }

    /// A narrow band of light swept across once, clipped to the card's own shape so it
    /// reads as the card catching the light rather than as something laid on top of it.
    private var sheen: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.55), .clear],
                startPoint: .leading, endPoint: .trailing)
                .frame(width: width * 0.45)
                .offset(x: shine * width * 0.72)
                .blendMode(.plusLighter)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .allowsHitTesting(false)
    }
}

extension View {
    /// Shows the flash over this view and clears it on its own.
    ///
    /// Self-clearing rather than tap-to-dismiss: there is nothing to act on, and a thing
    /// that needs dismissing is a thing that interrupted you.
    func memoryFlash(_ flash: Binding<AppModel.MemoryFlash?>) -> some View {
        overlay(alignment: .top) {
            if let current = flash.wrappedValue {
                MemoryFlash(kind: current.kind, text: current.text)
                    .id(current.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: current.id) {
                        try? await Task.sleep(for: .seconds(2.6))
                        flash.wrappedValue = nil
                    }
            }
        }
        .animation(.snappy(duration: 0.32), value: flash.wrappedValue?.id)
    }
}
