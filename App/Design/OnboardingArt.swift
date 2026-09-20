import SwiftUI
import RiveRuntime

/// The original reading rings settle into their done animation after a real Health read.
struct ReadingArt: View {
    var size: CGFloat = 214
    var isDone = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                if isDone {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: size * 0.55, weight: .light))
                        .foregroundStyle(Tokens.recoveryDeep)
                } else {
                    JettFace(size: size * 0.4)
                }
            } else {
                ReadingRive(size: size, isDone: isDone)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct ReadingRive: View {
    var size: CGFloat
    var isDone: Bool
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model = RiveViewModel(
        fileName: "Onboarding", stateMachineName: "Reading", artboardName: "Reading", loadCdn: false)

    var body: some View {
        ZStack {
            model.view()
            JettRive(size: size * 0.3, isThinking: !isDone)
                .background(Tokens.messageCanvas, in: Circle())
                // Match the centre of the rings in the 420pt Rive artboard.
                .offset(y: -22 * size / 420)
                .opacity(isDone ? 0 : 1)
                .animation(.easeOut(duration: 0.15), value: isDone)
        }
        .frame(width: size, height: size)
        .onAppear { push() }
        .onChange(of: isDone) { push() }
        .onChange(of: colorScheme) { push() }
    }

    private func push() {
        model.setInput("isDark", value: colorScheme == .dark)
        model.setInput("isDone", value: isDone)
    }
}
