import SwiftUI

/// The frame every question screen sits in.
///
/// One question per screen, a thin progress bar so the end is visible, and the action
/// pinned to the bottom where the thumb already is. The pattern is the standard
/// consumer-onboarding one; the point of standardising it here is that no screen gets
/// to invent its own layout and break the rhythm.
struct OnboardingScaffold<Content: View>: View {
    let progress: Double
    let title: String
    var subtitle: String?
    var canAdvance: Bool
    var actionTitle = "Continue"
    var onBack: (() -> Void)?
    var onSkip: (() -> Void)?
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                content
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            VStack(spacing: 10) {
                if let onSkip {
                    Button("Skip", action: onSkip)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Tokens.textSecondary)
                }
                PrimaryButton(label: actionTitle, enabled: canAdvance, action: action)
            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.canvas.ignoresSafeArea())
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Tokens.textPrimary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                ProgressTrack(progress: progress)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, Tokens.screenMargin)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }
}

/// How much of the flow is behind you. A hairline, not a chunky bar — it should
/// reassure, not dominate.
struct ProgressTrack: View {
    let progress: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.hairline)
                Capsule().fill(Tokens.textPrimary)
                    .frame(width: max(6, geometry.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 4)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: progress)
        .accessibilityLabel("Step progress")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }
}

/// A full-width choice. Plain by default, solid when chosen — the selected state is
/// unmistakable across the room, which is the whole job of an onboarding option.
struct ChoiceRow: View {
    let title: String
    var detail: String?
    var symbol: String?
    let isSelected: Bool
    var allowsMultiple = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(isSelected ? Tokens.onAccent : Tokens.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(isSelected ? Color.white.opacity(0.16) : Tokens.surfaceSunken,
                                    in: Circle())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isSelected ? Tokens.onAccent : Tokens.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(isSelected ? Tokens.onAccent.opacity(0.75)
                                                        : Tokens.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                if allowsMultiple {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 19))
                        .foregroundStyle(isSelected ? Tokens.onAccent : Tokens.hairline)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Tokens.textPrimary : Tokens.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(isSelected ? 0 : 0.05), radius: 10, x: 0, y: 2)
            .shadow(color: .black.opacity(isSelected ? 0 : 0.03), radius: 2, x: 0, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// A full-bleed screen that explains rather than asks. Used between question clusters
/// so the flow does not read as a form.
struct OnboardingStatement<Illustration: View>: View {
    let title: String
    /// Optional, because an illustration that works does not need a paragraph under it.
    var body_: String?
    var onBack: (() -> Void)?
    let progress: Double
    let action: () -> Void
    @ViewBuilder let illustration: Illustration

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Tokens.textPrimary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                }
                ProgressTrack(progress: progress)
            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.top, 8)

            Spacer()
            illustration
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Tokens.screenMargin)
            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let body_ {
                    Text(body_)
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.bottom, 24)

            PrimaryButton(label: "Continue", action: action)
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Tokens.canvas.ignoresSafeArea())
    }
}
