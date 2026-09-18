import SwiftUI
import SwiftData
import Charts

/// Shared shell so the three signal cards read as one system: one dominant idea each,
/// a value, its distance from the user's own baseline, a trend, and what is driving it.
struct SignalCard<Trend: View>: View {
    let title: String
    let value: String
    let unit: String?
    let delta: String?
    let deltaIsFavourable: Bool?
    let drivers: [String]
    @ViewBuilder var trend: Trend

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).sectionHeader()

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value)
                    .font(.system(.title, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textPrimary)
                if let unit { Text(unit).qualifier() }
                Spacer(minLength: 8)
                if let delta {
                    Text(delta)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(deltaIsFavourable == false ? Tokens.negative
                                         : (deltaIsFavourable == true ? Tokens.positive
                                            : Tokens.textSecondary))
                }
            }

            trend.frame(height: 34)

            if !drivers.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(drivers, id: \.self) { driver in
                        Text(driver).qualifier().fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value) \(unit ?? ""). \(delta ?? ""). "
                            + drivers.joined(separator: ". "))
    }
}

/// A trend line, not decoration. No axes, no grid — the shape is the point.
struct Sparkline: View {
    let values: [Double]
    var body: some View {
        if values.count < 2 {
            Text("Not enough history yet").qualifier()
        } else {
            Chart(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("Day", index), y: .value("Value", value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Tokens.accent)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Readiness

struct ReadinessScoreCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let composite = model.day?.readiness.composite ?? 0
        SignalCard(
            title: "Readiness",
            value: statePhrase,
            unit: nil,
            delta: composite.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always())) + " SD",
            deltaIsFavourable: composite >= 0,
            drivers: drivers) {
                Sparkline(values: model.compositeHistory())
            }
    }

    private var statePhrase: String {
        guard let state = model.day?.readiness.state else { return "—" }
        switch state {
        case .aboveBaseline: return "Above baseline"
        case .atBaseline: return "At baseline"
        case .belowBaseline: return "Below baseline"
        case .wellBelowBaseline: return "Well below"
        }
    }

    /// The leading positive and negative driver, which is what makes the number actionable.
    private var drivers: [String] {
        guard let contributions = model.day?.readiness.contributions, !contributions.isEmpty
        else { return [] }
        let sorted = contributions.sorted { $0.points < $1.points }
        var out: [String] = []
        if let worst = sorted.first, worst.points < -0.01 {
            out.append("Holding you back: " + Copy.describe(worst).lowercased())
        }
        if let best = sorted.last, best.points > 0.01 {
            out.append("Helping: " + Copy.describe(best).lowercased())
        }
        return out
    }
}

// MARK: - Sleep

struct SleepScoreCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let hours = model.latestSleepHours
        let debt = model.reading(.sleepDebt)
        SignalCard(
            title: "Sleep",
            value: hours.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
            unit: "h",
            delta: debt.map {
                ($0.zScore * -1).formatted(.number.precision(.fractionLength(1)).sign(strategy: .always())) + " SD"
            },
            deltaIsFavourable: debt.map { $0.zScore <= 0 },
            drivers: drivers) {
                Sparkline(values: model.sleepHoursSeries())
            }
    }

    private var drivers: [String] {
        guard let hours = model.latestSleepHours else { return [] }
        let need = DayAssembler.sleepNeedHours
        let gap = need - hours
        if gap > 0.25 {
            return ["\(gap.formatted(.number.precision(.fractionLength(1)))) h short of your \(Int(need)) h target"]
        }
        return ["At or above your \(Int(need)) h target"]
    }
}

// MARK: - Load

struct LoadScoreCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var sessions: [WorkoutSession]

    var body: some View {
        let weekly = weeklyVolume
        SignalCard(
            title: "Load",
            value: weekly > 0 ? formatted(weekly) : "—",
            unit: weekly > 0 ? "lb this week" : nil,
            delta: model.acwr.map { "ACWR " + $0.formatted(.number.precision(.fractionLength(2))) },
            deltaIsFavourable: model.acwr.map { $0 <= ReadinessEngine.acwrGate },
            drivers: drivers) {
                Sparkline(values: model.recentVolume(days: 14, context: context))
            }
    }

    private var weeklyVolume: Double {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -7, to: Date()) else { return 0 }
        return sessions.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.load.volumeLoad }
    }

    private func formatted(_ volume: Double) -> String {
        volume >= 10_000
            ? (volume / 1000).formatted(.number.precision(.fractionLength(1))) + "k"
            : volume.formatted(.number.precision(.fractionLength(0)))
    }

    private var drivers: [String] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -7, to: Date()) else { return [] }
        let recent = sessions.filter { $0.date >= cutoff }
        guard !recent.isEmpty else { return ["No sessions logged yet"] }

        var hardSets: [MuscleGroup: Int] = [:]
        for session in recent {
            for (muscle, count) in session.load.hardSetsByMuscle {
                hardSets[muscle, default: 0] += count
            }
        }
        guard let top = hardSets.max(by: { $0.value < $1.value }) else { return [] }
        var out = ["\(top.value) hard sets on \(top.key.displayName.lowercased()) this week"]
        if let acwr = model.acwr, acwr > ReadinessEngine.acwrGate {
            out.append("Load has climbed faster than your month-long average")
        }
        return out
    }
}
