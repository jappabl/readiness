import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingLog = false

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            content
        }
        .navigationTitle("")
        .toolbarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLog) {
            LogView(prescriptions: model.prescriptions)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().controlSize(.large).tint(Tokens.accent)
        case .needsLifts:
            OnboardingView()
                .navigationTitle("Your lifts")
                .navigationBarTitleDisplayMode(.inline)
        case .failed(let message):
            ContentUnavailableView("Nothing to read yet", systemImage: "heart.text.square",
                                   description: Text(message))
        case .ready:
            session
        }
    }

    private var session: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let day = model.day {
                    header(for: day)
                    prescriptionBlock
                }
                // At accessibility sizes a pinned button grows tall enough to cover the
                // prescription it refers to, so it rides along with the content instead.
                if typeSize.isAccessibilitySize {
                    logButton.padding(.top, 4)
                }
            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, typeSize.isAccessibilitySize ? 88 : 40)
        }
        .safeAreaInset(edge: .bottom) {
            if !typeSize.isAccessibilitySize { logBar }
        }
    }

    private var logButton: some View {
        Button {
            showingLog = true
        } label: {
            Text("Log this session")
                .font(.body.weight(.semibold))
                .foregroundStyle(Tokens.onAccent)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(Tokens.accent)
    }

    // MARK: - Readiness, expressed typographically and never chromatically (spec 9.4)

    private func header(for day: AssembledDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(day.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                .font(.footnote)
                .foregroundStyle(Tokens.textTertiary)

            NavigationLink {
                ExplainView(day: day)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(AppModel.phrase(for: day.readiness.state))
                            .font(.system(.title2, weight: .semibold))
                            .foregroundStyle(Tokens.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Tokens.textTertiary)
                    }
                    Text(AppModel.call(for: day.readiness))
                        .font(.body)
                        .foregroundStyle(Tokens.textSecondary)
                        .multilineTextAlignment(.leading)

                    if day.readiness.confidence == .low {
                        Text("Still calibrating — \(day.daysOfHistory) days of history.")
                            .qualifier()
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Readiness: \(AppModel.phrase(for: day.readiness.state)). \(AppModel.call(for: day.readiness))")
            .accessibilityHint("Shows how this was calculated")
        }
    }

    private var prescriptionBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Today")
                .sectionHeader()
            ForEach(Array(model.prescriptions.enumerated()), id: \.offset) { _, p in
                PrescriptionRowView(prescription: p)
            }
        }
    }

    private var logBar: some View {
        Group {
            if case .ready = model.phase, !model.prescriptions.isEmpty {
                logButton
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.bottom, 8)
            }
        }
    }
}

/// One lift. The load is the hero and nothing on the screen competes with it (spec 9.2).
struct PrescriptionRowView: View {
    let prescription: Prescription
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 52

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(prescription.lift.name)
                .font(.subheadline)
                .foregroundStyle(Tokens.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(prescription.prescribedLoad, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: heroSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.accent)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("lb").qualifier()
            }

            // One Text rather than an HStack of fragments: at accessibility sizes the
            // separators were wrapping onto lines of their own.
            Text(metadata)
                .font(.subheadline)
                .foregroundStyle(Tokens.textSecondary)
        }
        .card()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(prescription.lift.name), \(Int(prescription.prescribedLoad)) pounds, "
            + "\(prescription.repTarget) reps, \(prescription.rirTarget) reps in reserve")
    }

    private var metadata: String {
        var parts = ["\(prescription.repTarget) reps", "RIR \(prescription.rirTarget)"]
        if abs(prescription.appliedPercent) > 0.001 {
            parts.append(prescription.appliedPercent
                .formatted(.percent.precision(.fractionLength(1))))
        }
        return parts.joined(separator: " · ")
    }
}
