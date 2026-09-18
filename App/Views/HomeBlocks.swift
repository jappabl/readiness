import SwiftUI

/// The sections that vary by goal. Each one refuses to render a number the day does
/// not actually have — an empty macro card is better than a confident zero.

// MARK: - Energy balance

struct EnergyBalanceCard: View {
    let intake: Double?
    let active: Double?
    let basal: Double?

    private var out: Double? {
        guard active != nil || basal != nil else { return nil }
        return (active ?? 0) + (basal ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Energy").sectionHeading()
            if let intake, let out {
                let balance = intake - out
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(abs(balance), format: .number.precision(.fractionLength(0)))
                            .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Tokens.textPrimary)
                        Text(balance < 0 ? "kcal deficit" : "kcal surplus")
                            .font(.system(size: 14))
                            .foregroundStyle(Tokens.textSecondary)
                        Spacer(minLength: 0)
                    }
                    balanceBar(intake: intake, out: out)
                    HStack {
                        legend("In", intake, Tokens.jettTint)
                        Spacer()
                        legend("Out", out, Tokens.strainLow)
                    }
                }
                .bevelCard()
            } else {
                EmptyBlock(message: intake == nil
                           ? "No food logged today."
                           : "No activity recorded today.")
            }
        }
    }

    /// Two bars on a shared scale, so the gap between them is the message.
    private func balanceBar(intake: Double, out: Double) -> some View {
        let scale = max(intake, out, 1)
        return VStack(spacing: 6) {
            bar(intake / scale, Tokens.jettTint)
            bar(out / scale, Tokens.strainLow)
        }
    }

    private func bar(_ fraction: Double, _ tint: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.ringTrack)
                Capsule().fill(tint)
                    .frame(width: max(4, geometry.size.width * min(1, fraction)))
            }
        }
        .frame(height: 10)
    }

    private func legend(_ label: String, _ value: Double, _ tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label).font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
            Text(value, format: .number.precision(.fractionLength(0)))
                .font(.system(size: 13, weight: .medium)).monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
        }
    }
}

// MARK: - Protein

struct ProteinCard: View {
    let grams: Double?
    let bodyMassKg: Double?

    /// The usual evidence-backed band for someone training hard. Shown as a band
    /// rather than a single target, because the research does not give one.
    private static let band: ClosedRange<Double> = 1.6...2.2

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Protein").sectionHeading()
            if let grams {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(grams, format: .number.precision(.fractionLength(0)))
                            .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Tokens.textPrimary)
                        Text("g").font(.system(size: 15)).foregroundStyle(Tokens.textSecondary)
                        Spacer(minLength: 0)
                        if let ratio {
                            Text(ratio, format: .number.precision(.fractionLength(1)))
                                .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Tokens.textPrimary)
                            Text("g/kg").font(.system(size: 13))
                                .foregroundStyle(Tokens.textSecondary)
                        }
                    }
                    if let ratio {
                        bandBar(ratio)
                        Text(note(for: ratio))
                            .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                    }
                }
                .bevelCard()
            } else {
                EmptyBlock(message: "No food logged today.")
            }
        }
    }

    private var ratio: Double? {
        guard let grams, let bodyMassKg, bodyMassKg > 0 else { return nil }
        return grams / bodyMassKg
    }

    private func note(for ratio: Double) -> String {
        switch ratio {
        case ..<Self.band.lowerBound: return "Below the usual range for hard training"
        case Self.band:               return "In the usual range for hard training"
        default:                      return "Above the usual range — no harm in it"
        }
    }

    /// The band is drawn, not just described, so being under it is visible at a glance.
    private func bandBar(_ ratio: Double) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let scale = 3.0
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.ringTrack).frame(height: 8)
                Capsule().fill(Tokens.accent.opacity(0.18))
                    .frame(width: width * (Self.band.upperBound - Self.band.lowerBound) / scale,
                           height: 8)
                    .offset(x: width * Self.band.lowerBound / scale)
                Capsule().fill(Tokens.accent)
                    .frame(width: 3, height: 14)
                    .offset(x: min(width - 3, width * ratio / scale))
            }
            .frame(height: 14)
        }
        .frame(height: 14)
        .accessibilityHidden(true)
    }
}

// MARK: - Weight trend

struct WeightTrendCard: View {
    /// Oldest first.
    let series: [Double]

    private var recent: Double? { average(series.suffix(7)) }
    private var earlier: Double? { average(series.suffix(28).prefix(21)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weight").sectionHeading()
            if let recent {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(recent, format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Tokens.textPrimary)
                        Text("kg").font(.system(size: 15)).foregroundStyle(Tokens.textSecondary)
                        Spacer(minLength: 0)
                        if let change {
                            Text(change, format: .number.precision(.fractionLength(1))
                                .sign(strategy: .always()))
                                .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Tokens.textSecondary)
                            Text("kg / 3 wks").font(.system(size: 12))
                                .foregroundStyle(Tokens.textSecondary)
                        }
                    }
                    Sparkline(values: Array(series.suffix(28)), tint: Tokens.jettTint)
                        .frame(height: 38)
                    // A seven-day mean, because daily weight is mostly water and the
                    // day-to-day number is not a fact about fat.
                    Text("Seven-day average").qualifier()
                }
                .bevelCard()
            } else {
                EmptyBlock(message: "No weight recorded yet.")
            }
        }
    }

    private var change: Double? {
        guard let recent, let earlier else { return nil }
        return recent - earlier
    }

    private func average(_ values: some Collection<Double>) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Sleep quality

struct SleepQualityCard: View {
    let night: SleepBreakdown?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last night").sectionHeading()
            if let night, night.asleepHours > 0 {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(hours(night.asleepHours))
                            .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Tokens.textPrimary)
                        Spacer(minLength: 0)
                        if let efficiency = night.efficiency {
                            Text(efficiency, format: .percent.precision(.fractionLength(0)))
                                .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(Tokens.textPrimary)
                            Text("asleep in bed").font(.system(size: 12))
                                .foregroundStyle(Tokens.textSecondary)
                        }
                    }
                    stages(night)
                    HStack(spacing: 14) {
                        stageLegend("Deep", night.deepHours, Tokens.sleepDeep)
                        stageLegend("REM", night.remHours, Tokens.sleepLow)
                        stageLegend("Core", night.coreHours, Tokens.sleepHigh)
                        Spacer(minLength: 0)
                    }
                }
                .bevelCard()
            } else {
                EmptyBlock(message: "No sleep recorded last night.")
            }
        }
    }

    /// Deep first: it is the part people are actually asking about.
    private func stages(_ night: SleepBreakdown) -> some View {
        let total = max(night.asleepHours, 0.01)
        return GeometryReader { geometry in
            let width = geometry.size.width
            HStack(spacing: 2) {
                segment(width * night.deepHours / total, Tokens.sleepDeep)
                segment(width * night.remHours / total, Tokens.sleepLow)
                segment(width * night.coreHours / total, Tokens.sleepHigh)
            }
        }
        .frame(height: 12)
        .accessibilityHidden(true)
    }

    private func segment(_ width: Double, _ tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(tint)
            .frame(width: max(0, width - 2))
    }

    private func stageLegend(_ label: String, _ value: Double, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label).font(.system(size: 12)).foregroundStyle(Tokens.textSecondary)
            Text(hours(value)).font(.system(size: 12, weight: .medium)).monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
        }
    }

    private func hours(_ value: Double) -> String {
        let whole = Int(value)
        let minutes = Int((value - Double(whole)) * 60)
        return "\(whole)h \(minutes)m"
    }
}

// MARK: - Movement

struct MovementCard: View {
    let steps: Double?
    let distanceKm: Double?
    let exerciseMinutes: Double?
    let daylightMinutes: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movement").sectionHeading()
            if steps == nil && exerciseMinutes == nil {
                EmptyBlock(message: "No movement recorded today.")
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Tokens.cardGap),
                                    GridItem(.flexible(), spacing: Tokens.cardGap)],
                          spacing: Tokens.cardGap) {
                    if let steps {
                        StatCard(symbol: "figure.walk", label: "Steps",
                                 value: steps.formatted(.number.precision(.fractionLength(0))))
                    }
                    if let exerciseMinutes {
                        StatCard(symbol: "flame", label: "Exercise",
                                 value: exerciseMinutes.formatted(.number.precision(.fractionLength(0))),
                                 unit: "min")
                    }
                    if let distanceKm {
                        StatCard(symbol: "point.topleft.down.to.point.bottomright.curvepath",
                                 label: "Distance",
                                 value: distanceKm.formatted(.number.precision(.fractionLength(1))),
                                 unit: "km")
                    }
                    if let daylightMinutes {
                        StatCard(symbol: "sun.max", label: "Daylight",
                                 value: daylightMinutes.formatted(.number.precision(.fractionLength(0))),
                                 unit: "min")
                    }
                }
            }
        }
    }
}

// MARK: - Shared

/// Says what is missing rather than showing a confident zero.
struct EmptyBlock: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 14))
            .foregroundStyle(Tokens.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .bevelCard()
    }
}
