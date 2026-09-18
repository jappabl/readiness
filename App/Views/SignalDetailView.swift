import SwiftUI
import SwiftData
import Charts

/// One signal, in full. Hero figure, the measurements behind it, what it means for
/// today, and how it has moved.
struct SignalDetailView: View {
    let signal: Signal

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var sessions: [WorkoutSession]

    var body: some View {
        ZStack {
            SkyBackground(signal: signal)
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    HStack(spacing: 10) { chips }
                    CoachingBlock(title: "What it means",
                                  message: coaching,
                                  footnote: footnote)
                    trend
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.top, 4)
                .padding(.bottom, 92)
            }
        }
        .navigationTitle(signal.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 8) {
            RingGauge(signal: signal, percent: percent, caption: heroCaption,
                      lineWidth: 16, showsTitle: false)
                .frame(maxWidth: 210)
                .padding(.top, 8)
            Text(heroLine)
                .font(.subheadline)
                .foregroundStyle(Tokens.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var percent: Int? {
        switch signal {
        case .readiness: return model.readinessPercent
        case .sleep: return model.sleepPercent
        case .load: return model.loadPercent(context: context)
        }
    }

    private var heroCaption: String {
        switch signal {
        case .readiness: return "percentile"
        case .sleep: return "of need"
        case .load: return "of usual"
        }
    }

    private var heroLine: String {
        switch signal {
        case .readiness:
            let composite = model.day?.readiness.composite ?? 0
            let sd = composite.formatted(.number.precision(.fractionLength(2))
                .sign(strategy: .always()))
            guard let percent else { return "\(sd) SD from your baseline. Still calibrating." }
            return "\(sd) SD from your own baseline — better than \(percent)% of your days."
        case .sleep:
            guard let hours = model.latestSleepHours else { return "No sleep recorded last night." }
            // Reworded to sidestep a/an, since the target is configurable.
            return "You slept \(hours.formatted(.number.precision(.fractionLength(1)))) h of the "
                 + "\(Int(DayAssembler.sleepNeedHours)) h you need."
        case .load:
            return percent == nil
                ? "Log a few more sessions and this will compare your week against a typical one."
                : "This week's training volume against a typical week for you."
        }
    }

    // MARK: - Chips

    @ViewBuilder
    private var chips: some View {
        switch signal {
        case .readiness:
            StatChip(symbol: "waveform.path.ecg", label: "Resting HRV",
                     value: value(.hrv, unit: "ms"), tint: Tokens.readinessLow)
            StatChip(symbol: "heart", label: "Resting HR",
                     value: value(.restingHeartRate, unit: "bpm"), tint: Tokens.readinessLow)

        case .sleep:
            StatChip(symbol: "bed.double", label: "Duration",
                     value: model.latestSleepHours.map {
                         $0.formatted(.number.precision(.fractionLength(1))) + " h" } ?? "—",
                     tint: Tokens.sleepLow)
            StatChip(symbol: "hourglass", label: "Debt",
                     value: model.reading(.sleepDebt).map {
                         $0.value.formatted(.number.precision(.fractionLength(1))) + " h" } ?? "—",
                     tint: Tokens.sleepLow)

        case .load:
            StatChip(symbol: "scalemass", label: "Volume, 7d",
                     value: formattedVolume, tint: Tokens.loadLow)
            StatChip(symbol: "chart.line.uptrend.xyaxis", label: "Acute : chronic",
                     value: model.acwr.map {
                         $0.formatted(.number.precision(.fractionLength(2))) } ?? "—",
                     tint: Tokens.loadLow)
        }
    }

    private func value(_ kind: MetricKind, unit: String) -> String {
        guard let reading = model.reading(kind) else { return "—" }
        return reading.value.formatted(.number.precision(.fractionLength(1))) + " " + unit
    }

    private var weeklyVolume: Double {
        let daily = model.recentVolume(days: StrainEngine.chronicDays, context: context)
        return daily.suffix(StrainEngine.acuteDays).reduce(0, +)
    }

    private var formattedVolume: String {
        guard weeklyVolume > 0 else { return "—" }
        return weeklyVolume >= 10_000
            ? (weeklyVolume / 1000).formatted(.number.precision(.fractionLength(1))) + "k lb"
            : weeklyVolume.formatted(.number.precision(.fractionLength(0))) + " lb"
    }

    // MARK: - Coaching

    private var coaching: String {
        switch signal {
        case .readiness:
            guard let contributions = model.day?.readiness.contributions, !contributions.isEmpty,
                  let worst = contributions.min(by: { $0.points < $1.points })
            else { return "Not enough history to say yet." }
            return "\(Copy.describe(worst)) is the biggest thing holding today back. "
                 + (model.recommendation.map { Copy.call(for: $0, gate: model.day?.readiness.gateApplied) } ?? "")

        case .sleep:
            guard let hours = model.latestSleepHours else {
                return "No sleep was recorded last night, so it isn't voting on today's call."
            }
            let gap = DayAssembler.sleepNeedHours - hours
            return gap > 0.25
                ? "You were \(gap.formatted(.number.precision(.fractionLength(1)))) h short "
                  + "last night. Sleep debt is one of the five inputs behind today's call."
                : "You met your target last night, which is helping today's number."

        case .load:
            guard let acwr = model.acwr else {
                return "Log a few sessions and this will start comparing your week against your month."
            }
            return acwr > ReadinessEngine.acwrGate
                ? "Your last seven days are running well above your four-week average. "
                  + "That spike caps how far the app will let today's session climb."
                : "Your recent load is in the steady range against your four-week average."
        }
    }

    private var footnote: String? {
        switch signal {
        case .readiness:
            guard let day = model.day else { return nil }
            return "Model \(day.readiness.modelVersion) · \(day.daysOfHistory) days of history "
                 + "· confidence \(day.readiness.confidence.rawValue)"
        case .sleep, .load:
            return nil
        }
    }

    // MARK: - Trend

    private var trend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Last 14 days").sectionHeader()
            Group {
                switch signal {
                case .readiness:
                    Sparkline(values: model.compositeHistory(), tint: Tokens.readinessLow)
                        .frame(height: 110)
                case .sleep:
                    Sparkline(values: model.sleepHoursSeries(), tint: Tokens.sleepLow)
                        .frame(height: 110)
                case .load:
                    let volumes = model.recentVolume(days: 14, context: context)
                    if volumes.allSatisfy({ $0 == 0 }) {
                        Text("Log a session and this fills in.").qualifier()
                    } else {
                        Chart(Array(volumes.enumerated()), id: \.offset) { index, value in
                            BarMark(x: .value("Day", index), y: .value("Volume", value))
                                .foregroundStyle(Tokens.loadLow.opacity(0.8))
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 110)
                    }
                }
            }
            .card()
        }
    }
}
