import SwiftUI

/// The evidence behind today's call. Exists for the morning the app disagrees with how
/// the user feels — with no explanation they conclude it is broken and leave.
struct WhyView: View {
    let day: AssembledDay
    let recommendation: Recommendation

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        call
                        inputs
                        actions
                        uncertainty
                        provenance
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Why")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var call: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Copy.headline(for: recommendation.state))
                .font(.system(.title2, weight: .semibold))
                .foregroundStyle(Tokens.accent)
            Text(Copy.call(for: recommendation, gate: day.readiness.gateApplied))
                .font(.body)
                .foregroundStyle(Tokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What went into it").sectionHeader()
            VStack(spacing: 0) {
                ForEach(sorted, id: \.kind) { contribution in
                    row(for: contribution)
                    if contribution.kind != sorted.last?.kind {
                        Divider().overlay(Tokens.hairline)
                    }
                }
            }
            .card()

            HStack {
                Text("Total").font(.subheadline.weight(.semibold))
                Spacer()
                Text(day.readiness.composite, format: .number.precision(.fractionLength(3)))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            .foregroundStyle(Tokens.textPrimary)
            .padding(.horizontal, 4)

            Text("Contributions sum to the composite exactly. You can check the arithmetic.")
                .qualifier().padding(.horizontal, 4)
        }
    }

    private var sorted: [InputContribution] {
        day.readiness.contributions.sorted { $0.points < $1.points }
    }

    private func row(for contribution: InputContribution) -> some View {
        let reading = day.readings.first { $0.kind == contribution.kind }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(contribution.kind.displayName)
                    .font(.body).foregroundStyle(Tokens.textPrimary)
                Spacer()
                Text(contribution.points, format: .number.precision(.fractionLength(3)))
                    .font(.body).monospacedDigit().foregroundStyle(Tokens.textPrimary)
            }
            if let reading {
                Text(detail(reading, contribution)).qualifier()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func detail(_ reading: MetricReading, _ contribution: InputContribution) -> String {
        let value = reading.value.formatted(.number.precision(.fractionLength(1)))
        let baseline = reading.baseline.formatted(.number.precision(.fractionLength(1)))
        let z = reading.zScore.formatted(.number.precision(.fractionLength(2)))
        let weight = contribution.weight.formatted(.number.precision(.fractionLength(2)))
        return "\(value) \(reading.kind.unit) · baseline \(baseline) · z \(z) · weight \(weight)"
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What it proposes").sectionHeader()
            VStack(alignment: .leading, spacing: 6) {
                ForEach(recommendation.adjustments, id: \.self) { adjustment in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.footnote).foregroundStyle(Tokens.textTertiary)
                        Text(Copy.describe(adjustment))
                            .font(.body).foregroundStyle(Tokens.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private var uncertainty: some View {
        if !recommendation.uncertainty.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("What this can't see").sectionHeader()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(recommendation.uncertainty, id: \.self) { note in
                        Text(note).font(.subheadline).foregroundStyle(Tokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .card()
            }
        }
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let deviation = day.wristTemperatureDeviationC {
                Text(temperatureLine(deviation)).qualifier()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Model \(recommendation.modelVersion) · \(day.daysOfHistory) days of history "
                 + "· confidence \(recommendation.confidence.rawValue)")
                .font(.caption).foregroundStyle(Tokens.textTertiary)
            Text("Training guidance, not medical advice.")
                .font(.caption).foregroundStyle(Tokens.textTertiary)
        }
        .padding(.horizontal, 4)
    }

    private func temperatureLine(_ deviation: Double) -> String {
        let value = deviation.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
        let base = "Wrist temperature \(value) °C from baseline"
        guard day.readiness.gateApplied == .elevatedWristTemperature else { return base + "." }
        return base + " — above the illness threshold, which capped today."
    }
}
