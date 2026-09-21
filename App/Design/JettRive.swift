import SwiftUI
import RiveRuntime

/// Jett, animated.
///
/// The `.riv` carries one artboard and one state machine, both named "Jett", with three
/// inputs: `isThinking`, `isSpeaking` and `mood`. Blinking and breathing run inside the
/// file on their own timers, which is why there is no trigger for either here: the app
/// should never have to remember to make him blink.
struct JettRive: View {
    var size: CGFloat = 62
    var isThinking = false
    var isSpeaking = false
    /// 0 concerned, 1 neutral, 2 pleased.
    var mood: Double = 1

    @StateObject private var model = RiveViewModel(fileName: "Jett", stateMachineName: "Jett")

    var body: some View {
        model.view()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .onAppear { push() }
            .onChange(of: isThinking) { _, _ in push() }
            .onChange(of: isSpeaking) { _, _ in push() }
            .onChange(of: mood) { _, _ in push() }
            .accessibilityHidden(true)
    }

    private func push() {
        model.setInput("isThinking", value: isThinking)
        model.setInput("isSpeaking", value: isSpeaking)
        model.setInput("mood", value: mood)
    }
}

extension TrainingState {
    /// The mood input, from the day's call. A bad day shows on his face before he says
    /// anything, which is most of why a face is worth having at all.
    var jettMood: Double {
        switch self {
        case .recover, .reduce: return 0
        case .maintain:         return 1
        case .push:             return 2
        }
    }
}
