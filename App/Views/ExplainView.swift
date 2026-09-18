import SwiftUI

/// One tap from home. Transparency is a trust mechanism, not a daily feature: this
/// exists for the morning the model disagrees with how you feel (spec P6).
struct ExplainView: View {
    let day: AssembledDay

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summary
                    inputs
                    if let line = counterfactual { counterfactualCard(line) }
                    footnote
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.top, 8)
                // The tab bar floats over the scroll view; without this the footnote
                // has nothing left to scroll into and stays trapped behind it.
                .padding(.bottom, 72)
            }
        }
        .navigationTitle("Why")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppModel.phrase(for: day.readiness.state))
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(Tokens.textPrimary)
            HStack(spacing: 4) {
                Text("Composite")
                Text(day.readiness.composite, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                Text("SD from your baseline")
            }
            .qualifier()
        }
        .card()
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What went into it").sectionHeader()

            VStack(spacing: 0) {
                ForEach(sorted, id: \.kind) { c in
                    row(for: c)
                    if c.kind != sorted.last?.kind {
                        Divider().overlay(Tokens.hairline)
                    }
                }
            }
            .card()

            HStack {
                Text("Total")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(day.readiness.composite, format: .number.precision(.fractionLength(3)))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Tokens.textPrimary)
            .padding(.horizontal, 4)

            Text("Contributions sum to the composite exactly. You can check the arithmetic.")
                .qualifier()
                .padding(.horizontal, 4)
        }
    }

    private var sorted: [InputContribution] {
        day.readiness.contributions.sorted { $0.points < $1.points }
    }

    private func row(for c: InputContribution) -> some View {
        let reading = day.readings.first { $0.kind == c.kind }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(c.kind.displayName)
                    .font(.body)
                    .foregroundStyle(Tokens.textPrimary)
                Spacer()
                Text(c.points, format: .number.precision(.fractionLength(3)))
                    .font(.body)
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textPrimary)
            }
            if let reading {
                HStack(spacing: 4) {
                    Text(reading.value, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                    Text(c.kind.unit)
                    Text("· baseline")
                    Text(reading.baseline, format: .number.precision(.fractionLength(1)))
                        .monospacedDigit()
                    Text("· z")
                    Text(reading.zScore, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                    Text("· weight")
                    Text(c.weight, format: .number.precision(.fractionLength(2)))
                        .monospacedDigit()
                }
                .qualifier()
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(c.kind.displayName): contributed \(String(format: "%.3f", c.points)) points"
            + (reading.map { ", z score \(String(format: "%.2f", $0.zScore))" } ?? ""))
    }

    /// The single largest negative contributor, and what today would read without it.
    private var counterfactual: String? {
        guard let worst = day.readiness.contributions.min(by: { $0.points < $1.points }),
              worst.points < -0.01 else { return nil }

        let neutralised = day.readings.map { reading -> MetricReading in
            guard reading.kind == worst.kind else { return reading }
            return MetricReading(kind: reading.kind, value: reading.value,
                                 baseline: reading.baseline, zScore: 0,
                                 sampleCount: reading.sampleCount)
        }
        let without = ReadinessEngine.evaluate(
            ReadinessInput(readings: neutralised,
                           wristTemperatureDeviationC: day.wristTemperatureDeviationC,
                           daysOfHistory: day.daysOfHistory))

        guard without.state != day.readiness.state else {
            return "\(worst.kind.displayName) is today's biggest drag, but bringing it back to "
                 + "baseline alone would not change the call."
        }
        return "\(worst.kind.displayName) is today's biggest drag. Back at your baseline, "
             + "today would read \(AppModel.phrase(for: without.state).lowercased())."
    }

    private func counterfactualCard(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What would flip it").sectionHeader()
            Text(line)
                .font(.body)
                .foregroundStyle(Tokens.textPrimary)
                .card()
        }
    }

    /// One string rather than an HStack of fragments, which wrapped into a mess.
    private var temperatureLine: String? {
        guard let deviation = day.wristTemperatureDeviationC else { return nil }
        let value = deviation.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
        let base = "Wrist temperature \(value) °C from baseline"
        guard day.readiness.gateApplied == .elevatedWristTemperature else { return base + "." }
        return base + " — above the illness threshold, which capped today."
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let line = temperatureLine {
                Text(line).qualifier()
            }
            Text("Model \(day.readiness.modelVersion) · \(day.daysOfHistory) days of history · "
                 + "confidence \(day.readiness.confidence.rawValue)")
                .font(.caption)
                .foregroundStyle(Tokens.textTertiary)
            Text("Training guidance, not medical advice.")
                .font(.caption)
                .foregroundStyle(Tokens.textTertiary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}
