import SwiftUI

/// The sections that vary by goal. Each one refuses to render a number the day does
/// not actually have — an empty macro card is better than a confident zero.

// MARK: - Nutrition

struct NutritionCard: View {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let onLog: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nutrition").sectionHeading(); Spacer()
                Button(action: onLog) { Label("Log meal", systemImage: "camera").font(.subheadline.weight(.semibold)) }
                    .sectionAction()
            }
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // Zero, not a dash. The app's rule everywhere else is that a missing
                    // measurement must never render as a confident zero — but nutrition
                    // is not measured, it is logged, and an empty log is a log of
                    // nothing. Nought calories is the true answer, and a dash makes the
                    // user wonder whether the app failed to read something.
                    Text((calories ?? 0).formatted(.number.precision(.fractionLength(0))))
                        .font(.system(size: 32, weight: .semibold)).monospacedDigit()
                    Text("kcal logged").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(spacing: 0) {
                    macro("Protein", protein); Divider().frame(height: 32)
                    macro("Carbs", carbs); Divider().frame(height: 32)
                    macro("Fat", fat)
                }
                if calories == nil { Text("Add your first meal, or sync a food log from Health.").font(.footnote).foregroundStyle(.secondary) }
            }.bevelCard()
        }
    }
    private func macro(_ name: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.caption).foregroundStyle(.secondary)
            Text("\((value ?? 0).formatted(.number.precision(.fractionLength(0)))) g")
                .font(.headline).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, name == "Protein" ? 0 : 16)
    }
}

// MARK: - Weight

struct WeightTrendCard: View {
    let latest: (date: Date, kilograms: Double)?
    let series: [Double]
    let metric: Bool
    let onLog: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Weight").sectionHeading(); Spacer()
                Button("Log weight", systemImage: "plus", action: onLog)
                    .font(.subheadline.weight(.semibold)).sectionAction()
            }
            VStack(alignment: .leading, spacing: 12) {
                if let latest {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(BodyMass.display(kilograms: latest.kilograms, metric: metric), format: .number.precision(.fractionLength(1)))
                            .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                        Text(metric ? "kg" : "lb").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(latest.date, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary)
                    }
                    if series.count > 1 {
                        Sparkline(values: Array(series.suffix(28)), tint: Tokens.jettTint).frame(height: 36)
                        Text("Recent readings").font(.caption).foregroundStyle(.secondary)
                    }
                } else { Text("Add a weigh-in to start your trend.").font(.subheadline).foregroundStyle(.secondary) }
            }.bevelCard()
        }
    }
}

// MARK: - Sleep quality

struct SleepQualityCard: View {
    let night: SleepBreakdown?
    let summary: String

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
                    Text(summary).font(.footnote).foregroundStyle(.secondary)
                    if night.deepHours + night.remHours + night.coreHours > 0 {
                    stages(night)
                    HStack(spacing: 14) {
                        stageLegend("Deep", night.deepHours, Tokens.sleepDeep)
                        stageLegend("REM", night.remHours, Tokens.sleepLow)
                        stageLegend("Core", night.coreHours, Tokens.sleepHigh)
                        Spacer(minLength: 0)
                    }
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
    let activeEnergy: Double?
    let steps: Double?
    let exerciseMinutes: Double?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Movement").sectionHeading()
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "flame.fill").foregroundStyle(Tokens.textPrimary)
                    Text(activeEnergy.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—")
                        .font(.system(size: 30, weight: .semibold)).monospacedDigit()
                    Text("active kcal").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack {
                    Label(steps.map { "\($0.formatted(.number.precision(.fractionLength(0)))) steps" } ?? "No steps yet", systemImage: "figure.walk")
                    Spacer()
                    Label(exerciseMinutes.map { "\($0.formatted(.number.precision(.fractionLength(0)))) min" } ?? "No exercise yet", systemImage: "figure.run")
                }.font(.subheadline).foregroundStyle(.secondary)
                // No summary line under the two that already said it. "No steps yet, no
                // exercise yet, no movement recorded today" is the same sentence three
                // times, and the third one is the only one carrying no number.
            }.bevelCard(padding: 18)
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

// MARK: - Sleep debt

/// What you are down on sleep, and which way it went.
///
/// This used to live inside the sleep score, where it made two identical nights score
/// differently for a reason nobody could act on that night — and measured over sixty
/// nights it flipped a constant sleeper's band on 44% of them. A stock does not belong
/// inside a flow. Here it is what it actually is: a balance with a direction.
struct SleepDebtCard: View {
    let debt: SleepDebt

    /// Silent when there is nothing owed and nothing moved. A card that says "0 h, no
    /// change" every morning teaches people to stop reading cards.
    private var worthShowing: Bool { debt.hours >= 0.25 || abs(debt.change) >= 0.25 }

    var body: some View {
        if worthShowing {
            VStack(alignment: .leading, spacing: 12) {
                Text("Sleep debt").sectionHeading()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(hours(debt.hours))
                        .font(.system(size: 32, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Tokens.textPrimary)
                    Text("h behind").font(.subheadline).foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if abs(debt.change) >= 0.05 { delta }
                }
                .bevelCard()
            }
        }
    }

    /// Down is good here, which is the opposite of everywhere else in the app — so the
    /// arrow points the way the number moved and the colour says whether that was good.
    private var delta: some View {
        let paidDown = debt.change < 0
        return HStack(spacing: 3) {
            Image(systemName: paidDown ? "arrow.down" : "arrow.up")
                .font(.system(size: 13, weight: .bold))
            Text(hours(abs(debt.change)) + " h")
                .font(.system(size: 15, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(paidDown ? Tokens.recoveryHigh : Tokens.alert)
        // "Since yesterday", which is what it is: `SleepDebt.of` takes one reference and
        // measures both balances against it, so this really is how the balance moved
        // between the two days.
        //
        // What it is *not* is last night's own contribution, which the previous label
        // claimed. Two overlapping seven-night windows differ by the night arriving and
        // the night rolling off the far end, and measured over ninety nights the roll-off
        // explained more of the movement than last night did on 40-59% of the days an
        // arrow appeared. After a bad week it read "down 3.5 hours after last night" on
        // two consecutive mornings when last night was exactly this sleeper's median and
        // contributed nothing at all.
        .accessibilityLabel(paidDown
            ? "Down \(hours(abs(debt.change))) hours since yesterday"
            : "Up \(hours(abs(debt.change))) hours since yesterday")
    }

    private func hours(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
