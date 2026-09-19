import SwiftUI
import SwiftData

/// The flow, in the order that earns the right to ask.
///
/// What the app does, then what you want from it, then how you train, then what gets in
/// the way — and only then access to six months of your physiology. Asking Health on
/// launch, before saying anything, is how a health app gets declined on its first
/// screen and never recovers.
///
/// It ends on the user's own baselines rather than a promise. Every other app in this
/// category closes onboarding with a projection; this one closes with six months of
/// measurements it just read, which is the actual product.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    private enum Step: Int, CaseIterable {
        case welcome, goal, frequency, obstacles, method, units, health, reading, baselines
    }

    @State private var step: Step = .welcome
    @State private var answers = OnboardingAnswers()
    @State private var connecting = false

    var body: some View {
        Group {
            switch step {
            case .welcome:   welcome
            case .goal:      goalStep
            case .frequency: frequencyStep
            case .obstacles: obstaclesStep
            case .method:    methodStep
            case .units:     unitsStep
            case .health:    healthStep
            case .reading:   readingStep
            case .baselines: baselinesStep
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: step)
    }

    /// Questions only — the welcome and the reveal are not steps you are "through".
    private func progress(_ current: Step) -> Double {
        let questions: [Step] = [.goal, .frequency, .obstacles, .method, .units, .health]
        guard let index = questions.firstIndex(of: current) else { return 1 }
        return Double(index + 1) / Double(questions.count)
    }

    private func advance(to next: Step) {
        Haptics.light()
        step = next
    }

    // MARK: - Welcome

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            JettRive(size: 84)
            Text("Readiness")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Tokens.textPrimary)
                .padding(.top, 24)
            Text("See what's happening in your body,\nand know what to do about it today.")
                .font(.system(size: 16))
                .foregroundStyle(Tokens.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 10)
            Spacer()
            PrimaryButton(label: "Get started") { advance(to: .goal) }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.canvas.ignoresSafeArea())
    }

    // MARK: - Questions

    private var goalStep: some View {
        OnboardingScaffold(
            progress: progress(.goal),
            title: "What are you here for?",
            subtitle: "This decides what you see first. You can change it later.",
            canAdvance: answers.goal != nil,
            onBack: { advance(to: .welcome) },
            action: { advance(to: .frequency) }
        ) {
            VStack(spacing: 10) {
                ForEach(TrainingGoal.allCases, id: \.self) { goal in
                    ChoiceRow(title: goal.title, detail: goal.promise, symbol: goal.symbol,
                              isSelected: answers.goal == goal) {
                        Haptics.decided()
                        answers.goal = goal
                    }
                }
            }
        }
    }

    private var frequencyStep: some View {
        OnboardingScaffold(
            progress: progress(.frequency),
            title: "How many days a week do you train?",
            subtitle: "So a hard week isn't mistaken for a bad one.",
            canAdvance: answers.frequency != nil,
            onBack: { advance(to: .goal) },
            action: { advance(to: .obstacles) }
        ) {
            VStack(spacing: 10) {
                ForEach(TrainingFrequency.allCases, id: \.self) { frequency in
                    ChoiceRow(title: frequency.title, detail: frequency.detail,
                              symbol: frequency.symbol,
                              isSelected: answers.frequency == frequency) {
                        Haptics.decided()
                        answers.frequency = frequency
                    }
                }
            }
        }
    }

    private var obstaclesStep: some View {
        OnboardingScaffold(
            progress: progress(.obstacles),
            title: "What gets in the way?",
            subtitle: "Pick any. Jett keeps these in mind, and never scores them.",
            canAdvance: true,
            onBack: { advance(to: .frequency) },
            onSkip: { advance(to: .method) },
            action: { advance(to: .method) }
        ) {
            VStack(spacing: 10) {
                ForEach(Obstacle.allCases, id: \.self) { obstacle in
                    ChoiceRow(title: obstacle.title, symbol: obstacle.symbol,
                              isSelected: answers.obstacles.contains(obstacle),
                              allowsMultiple: true) {
                        Haptics.light()
                        if answers.obstacles.contains(obstacle) {
                            answers.obstacles.remove(obstacle)
                        } else {
                            answers.obstacles.insert(obstacle)
                        }
                    }
                }
            }
        }
    }

    /// The differentiator, stated plainly. No invented statistic — every other app in
    /// this category puts a fabricated retention number here, and we do not have one.
    private var methodStep: some View {
        OnboardingStatement(
            title: "Measured against you",
            body_: "Your normal, built from your own nights.",
            onBack: { advance(to: .obstacles) },
            progress: progress(.method),
            action: { advance(to: .units) }
        ) {
            BaselineArt()
        }
    }

    private var unitsStep: some View {
        OnboardingScaffold(
            progress: progress(.units),
            title: "Pounds or kilos?",
            subtitle: "Used for loads on the bar and for your weight.",
            canAdvance: true,
            onBack: { advance(to: .method) },
            action: { advance(to: .health) }
        ) {
            VStack(spacing: 10) {
                ChoiceRow(title: "Pounds", detail: "lb · 2.5 lb plates",
                          symbol: "scalemass", isSelected: !answers.unitsAreMetric) {
                    Haptics.decided()
                    answers.unitsAreMetric = false
                }
                ChoiceRow(title: "Kilos", detail: "kg · 1.25 kg plates",
                          symbol: "scalemass.fill", isSelected: answers.unitsAreMetric) {
                    Haptics.decided()
                    answers.unitsAreMetric = true
                }
            }
        }
    }

    // MARK: - Health

    private var healthStep: some View {
        OnboardingScaffold(
            progress: progress(.health),
            title: "Connect Health",
            subtitle: "Read on this device and kept on it. Nothing is uploaded.",
            canAdvance: !connecting,
            actionTitle: connecting ? "Connecting…" : "Connect Health",
            onBack: { advance(to: .units) },
            action: connect
        ) {
            // No chips under it: the picture names its own three sources, and a
            // caption that repeats the illustration is the thing to cut first.
            PrivateArt()
                .padding(.top, 2)
        }
    }

    /// The read is usually faster than a frame, which made the screen that explains it
    /// flash past like a glitch. Held just long enough to be read as a step rather than
    /// a stutter, and no longer than somebody would wait without wondering.
    private static let readingDwell: Duration = .milliseconds(1300)

    private func connect() {
        connecting = true
        model.completeOnboarding(answers, in: context)
        advance(to: .reading)
        Task {
            let began = ContinuousClock.now
            await model.refresh()
            model.startBackgroundDelivery()
            let remaining = Self.readingDwell - began.duration(to: .now)
            if remaining > .zero { try? await Task.sleep(for: remaining) }
            connecting = false
            Haptics.committed()
            advance(to: .baselines)
        }
    }

    // MARK: - The reveal

    private var readingStep: some View {
        VStack(spacing: 26) {
            Spacer()
            ReadingArt()
            Text("Reading your history")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Tokens.textPrimary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.canvas.ignoresSafeArea())
    }

    /// Real numbers, read from the device a second ago. The entire pitch of the app is
    /// that it uses your own history — so the last thing onboarding does is show it.
    private var baselinesStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(Tokens.accent)
                        Text(headline)
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(Tokens.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subhead)
                            .font(.system(size: 15))
                            .foregroundStyle(Tokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 20)

                    if let day = model.day, !day.readings.isEmpty {
                        ListCard {
                            ForEach(Array(day.readings.enumerated()), id: \.element.kind) { index, reading in
                                if index > 0 {
                                    Divider().overlay(Tokens.hairline).padding(.leading, 14)
                                }
                                FieldRow(label: reading.kind.displayName) {
                                    Text(reading.baseline.formatted(.number.precision(.fractionLength(1)))
                                         + " " + reading.kind.unit)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.bottom, 24)
            }
            PrimaryButton(label: "Start") { model.finishOnboarding() }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.canvas.ignoresSafeArea())
    }

    private var headline: String {
        guard let day = model.day else { return "You're set up" }
        return "\(Copy.count(day.daysOfHistory, "day")) of your history, read"
    }

    private var subhead: String {
        guard let day = model.day else {
            return "No history on this phone yet. Wear your watch tonight and Readiness "
                 + "will have something to say tomorrow."
        }
        switch day.readiness.confidence {
        case .low:
            return "Enough to start, not enough to be sure. These baselines sharpen every night."
        default:
            return "These are your baselines. Every number in the app is measured against them."
        }
    }
}
