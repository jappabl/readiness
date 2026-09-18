import SwiftUI

/// The evidence behind today's call, for the morning the app disagrees with how you feel.
///
/// Read top to bottom it answers three questions in order: what should I do, what is
/// that based on, and what could it be missing. The model's internals — weights,
/// points, the composite total — are deliberately not on this screen. They explain how
/// the arithmetic works, not why today is what it is, and they crowded out the part
/// that does.
struct WhyView: View {
    let day: AssembledDay
    let recommendation: Recommendation

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var editingCheckIn = false

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        verdict
                        evidence
                        uncertainty
                        provenance
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
            .sheet(isPresented: $editingCheckIn) { CheckInView() }
            .navigationTitle("Why")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Tokens.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold)).tint(Tokens.accent)
                }
            }
        }
    }

    // MARK: - The call, resting on the plan

    /// The same layered pair as Today: two surfaces, the top one shadowing the one
    /// beneath, so the call reads as sitting *on* the plan rather than beside it.
    private var verdict: some View {
        VStack(spacing: -18) {
            call.zIndex(1)
            plan
        }
    }

    private var readinessPercent: Int? {
        max(1, Percentile.percent(fromZ: day.readiness.composite))
    }

    private var call: some View {
        HStack(spacing: 16) {
            RingGauge(signal: .recovery, percent: readinessPercent,
                      lineWidth: 9, figureSize: 22)
                .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 4) {
                Text(Copy.headline(for: recommendation.state))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Tokens.textPrimary)
                Text(Copy.call(for: recommendation, gate: day.readiness.gateApplied))
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.cardRadius,
                                                         style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 4)
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The plan").microLabel()
            ForEach(recommendation.adjustments, id: \.self) { adjustment in
                HStack(spacing: 12) {
                    Image(systemName: Copy.symbol(for: adjustment))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Tokens.accent)
                        .frame(width: 32, height: 32)
                        .background(Tokens.accent.opacity(0.12), in: Circle())
                    Text(Copy.describe(adjustment))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Tokens.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .padding(.top, 31)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.cardRadius,
                                                         style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }

    // MARK: - Evidence

    /// Biggest mover first, whichever way it moved — on a good day the reason is a
    /// metric that went up.
    private var ranked: [InputContribution] {
        day.readiness.contributions.sorted { abs($0.points) > abs($1.points) }
    }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What it read").sectionHeading()
            ListCard {
                ForEach(Array(ranked.enumerated()), id: \.element.kind) { index, contribution in
                    if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                    row(for: contribution)
                }
                Divider().overlay(Tokens.hairline).padding(.leading, 14)
                felt
            }
        }
    }

    /// What the user reported this morning, shown here rather than on Today: it is an
    /// input to the decision, and repeating someone's own answer back to them anywhere
    /// else is just an echo.
    private var felt: some View {
        Button { editingCheckIn = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Tokens.textSecondary.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("How you felt")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Tokens.textPrimary)
                    Text(feltNote)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint(model.todayCheckIn == nil ? "Check in" : "Edit your check-in")
    }

    private var feltNote: String {
        guard let checkIn = model.todayCheckIn else { return "Not answered yet" }
        let mean = Double(checkIn.soreness + checkIn.energy + checkIn.stress + checkIn.mood) / 4
        let shift = RecommendationEngine.checkInShift(checkIn)
        let word: String
        switch mean {
        case ..<1.75: word = "Rough"
        case ..<2.5:  word = "Low"
        case ..<3.5:  word = "Okay"
        case ..<4.25: word = "Good"
        default:      word = "Strong"
        }
        switch shift {
        case 0.05...:     return "\(word) — nudged the call up"
        case ..<(-0.05):  return "\(word) — nudged the call down"
        default:          return "\(word) — didn't move the call"
        }
    }

    private func row(for contribution: InputContribution) -> some View {
        let reading = day.readings.first { $0.kind == contribution.kind }
        let tint = contribution.points < 0 ? Tokens.negative : Tokens.positive
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Image(systemName: Copy.symbol(for: contribution.kind))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.12), in: Circle())
                Text(contribution.kind.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tokens.textPrimary)
                Spacer(minLength: 8)
                if let reading {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(reading.value, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Tokens.textPrimary)
                        Text(reading.kind.unit)
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.textSecondary)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                RangeBar(z: contribution.zScore,
                         polarity: contribution.kind.polarity,
                         tint: tint)
                Text(Copy.deviationPhrase(contribution.zScore))
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.textSecondary)
            }
            .padding(.leading, 36)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Limits

    @ViewBuilder
    private var uncertainty: some View {
        if !recommendation.uncertainty.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("What it can't see").sectionHeading()
                ListCard {
                    ForEach(Array(recommendation.uncertainty.enumerated()), id: \.element) { index, note in
                        if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                        Text(note)
                            .font(.system(size: 14))
                            .foregroundStyle(Tokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let deviation = day.wristTemperatureDeviationC {
                Text(temperatureLine(deviation))
                    .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Model \(recommendation.modelVersion) · \(Copy.count(day.daysOfHistory, "day")) · "
                 + "confidence \(recommendation.confidence.rawValue)")
                .font(.system(size: 12)).foregroundStyle(Tokens.textTertiary)
        }
        .padding(.horizontal, 2)
    }

    private func temperatureLine(_ deviation: Double) -> String {
        let value = deviation.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
        let base = "Wrist temperature \(value) °C from baseline"
        guard day.readiness.gateApplied == .elevatedWristTemperature else { return base + "." }
        return base + " — above the illness threshold, which capped today."
    }
}
