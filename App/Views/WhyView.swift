import SwiftUI

/// The evidence behind today's call, for the morning the app disagrees with how you feel.
struct WhyView: View {
    let day: AssembledDay
    let recommendation: Recommendation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        call
                        inputs
                        proposals
                        uncertainty
                        provenance
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
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

    private var call: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Copy.headline(for: recommendation.state))
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(Tokens.accent)
            Text(Copy.call(for: recommendation, gate: day.readiness.gateApplied))
                .font(.system(size: 15))
                .foregroundStyle(Tokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bevelCard()
    }

    private var sorted: [InputContribution] {
        day.readiness.contributions.sorted { $0.points < $1.points }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What went into it").sectionHeading()
            ListCard {
                ForEach(Array(sorted.enumerated()), id: \.element.kind) { index, contribution in
                    if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                    row(for: contribution)
                }
                Divider().overlay(Tokens.hairline)
                HStack {
                    Text("Total").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(day.readiness.composite, format: .number.precision(.fractionLength(3)))
                        .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                }
                .foregroundStyle(Tokens.textPrimary)
                .padding(.horizontal, 14).padding(.vertical, 12)
            }
            Text("Contributions sum to the composite exactly. You can check the arithmetic.")
                .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                .padding(.horizontal, 2)
        }
    }

    private func row(for contribution: InputContribution) -> some View {
        let reading = day.readings.first { $0.kind == contribution.kind }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(contribution.kind.displayName)
                    .font(.system(size: 15)).foregroundStyle(Tokens.textPrimary)
                Spacer()
                Text(contribution.points, format: .number.precision(.fractionLength(3)))
                    .font(.system(size: 15)).monospacedDigit()
                    .foregroundStyle(contribution.points < 0 ? Tokens.negative : Tokens.positive)
            }
            if let reading {
                Text(detail(reading, contribution))
                    .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private func detail(_ reading: MetricReading, _ contribution: InputContribution) -> String {
        let value = reading.value.formatted(.number.precision(.fractionLength(1)))
        let baseline = reading.baseline.formatted(.number.precision(.fractionLength(1)))
        let z = reading.zScore.formatted(.number.precision(.fractionLength(2)))
        let weight = contribution.weight.formatted(.number.precision(.fractionLength(2)))
        return "\(value) \(reading.kind.unit) · baseline \(baseline) · z \(z) · weight \(weight)"
    }

    private var proposals: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What it proposes").sectionHeading()
            ListCard {
                ForEach(Array(recommendation.adjustments.enumerated()), id: \.element) { index, adjustment in
                    if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 12)).foregroundStyle(Tokens.accent)
                        Text(Copy.describe(adjustment))
                            .font(.system(size: 15)).foregroundStyle(Tokens.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
            }
        }
    }

    @ViewBuilder
    private var uncertainty: some View {
        if !recommendation.uncertainty.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("What this can't see").sectionHeading()
                ListCard {
                    ForEach(Array(recommendation.uncertainty.enumerated()), id: \.element) { index, note in
                        if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                        Text(note)
                            .font(.system(size: 15)).foregroundStyle(Tokens.textSecondary)
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
            Text("Training guidance, not medical advice.")
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
