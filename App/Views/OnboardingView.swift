import SwiftUI
import SwiftData

/// Three screens, in the order that earns the right to ask.
///
/// What the app does, then what you want out of it, then — and only then — access to
/// six months of your physiology. Asking for Health on launch, before saying anything,
/// is how a health app gets declined on its first screen and never recovers.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @State private var step = 0
    @State private var chosen: TrainingGoal?
    @State private var connecting = false

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                switch step {
                case 0:  welcome
                case 1:  goalPicker
                default: healthAccess
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: step)
    }

    // MARK: - 1. What this is

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            JettOrb(size: 76)
            Text("Readiness")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Tokens.textPrimary)
                .padding(.top, 22)
            Text("See what's happening in your body,\nand know what to do about it today.")
                .font(.system(size: 16))
                .foregroundStyle(Tokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

            Spacer()

            VStack(spacing: 18) {
                point("bed.double", "Your night, read properly",
                      "Stages, not just hours.")
                point("waveform.path.ecg", "Scored against you",
                      "Your own baseline, never a population average.")
                point("figure.strengthtraining.traditional", "One clear call",
                      "What to do today, and why.")
            }
            .padding(.horizontal, 30)

            Spacer()
            PrimaryButton(label: "Get started") { step = 1 }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.bottom, 16)
        }
    }

    private func point(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Tokens.jettTint)
                .frame(width: 34, height: 34)
                .background(Tokens.jettTint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
                Text(detail).font(.system(size: 14))
                    .foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - 2. What you want

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("What are you here for?",
                   "It decides what you see first. You can change it later.")

            VStack(spacing: Tokens.cardGap) {
                ForEach(TrainingGoal.allCases, id: \.self) { goal in
                    Button {
                        Haptics.decided()
                        chosen = goal
                    } label: {
                        goalRow(goal)
                    }
                    .buttonStyle(PressableStyle())
                }
            }
            .padding(.horizontal, Tokens.screenMargin)

            Spacer()

            PrimaryButton(label: "Continue", enabled: chosen != nil) { step = 2 }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.bottom, 16)
        }
    }

    private func goalRow(_ goal: TrainingGoal) -> some View {
        let selected = chosen == goal
        return HStack(spacing: 14) {
            Image(systemName: goal.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(selected ? Tokens.onAccent : Tokens.textSecondary)
                .frame(width: 40, height: 40)
                .background(selected ? Tokens.accent : Tokens.surfaceSunken, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
                Text(goal.promise)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.cardRadius,
                                                         style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous)
            .strokeBorder(selected ? Tokens.accent : .clear, lineWidth: 2))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }

    // MARK: - 3. Why it needs Health

    private var healthAccess: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Connect Health",
                   "Everything is read on this device and stays on it. Nothing is uploaded.")

            VStack(spacing: 18) {
                point("moon.zzz", "Sleep and overnight vitals",
                      "The night is most of the signal.")
                point("heart", "Heart rate and variability",
                      "Compared only against your own history.")
                point("flame", "Activity and training",
                      "So a hard week is not read as a bad one.")
            }
            .padding(.horizontal, 30)

            Spacer()

            VStack(spacing: 10) {
                PrimaryButton(label: connecting ? "Connecting…" : "Connect Health",
                              enabled: !connecting) {
                    connect()
                }
                Text("Readiness needs at least a couple of nights before it can say anything.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.bottom, 16)
        }
    }

    private func connect() {
        guard let goal = chosen else { return }
        connecting = true
        model.setGoal(goal, in: context)
        Task {
            await model.refresh()
            model.startBackgroundDelivery()
            connecting = false
        }
    }

    private func header(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Tokens.textPrimary)
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(Tokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Tokens.screenMargin)
        .padding(.top, 28)
        .padding(.bottom, 24)
    }
}
