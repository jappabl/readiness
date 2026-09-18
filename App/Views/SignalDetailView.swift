import SwiftUI
import SwiftData
import Charts

/// One signal in full: sky, hero ring, two figures, a short coaching note, timeline.
struct SignalDetailView: View {
    let signal: Signal

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var sessions: [WorkoutSession]

    @State private var showingWhy = false

    var body: some View {
        ZStack {
            SkyBackground(signal: signal)
            ScrollView {
                VStack(spacing: 16) {
                    HeroRing(signal: signal, percent: percent)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                    HStack(spacing: Tokens.cardGap) { figures }
                    CoachCard(message: coaching,
                              accessory: (label: "View insights", symbol: "sparkles"),
                              action: { showingWhy = true })
                    timeline
                    trends
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.bottom, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(signal.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Tokens.textPrimary)
                    HStack(spacing: 4) {
                        Text(Date(), format: .dateTime.month(.wide).day())
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.textSecondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingWhy = true } label: {
                    Image(systemName: "info.circle").font(.system(size: 16))
                }
                .tint(Tokens.textPrimary)
                .accessibilityLabel("How this is calculated")
            }
        }
        .sheet(isPresented: $showingWhy) {
            if let day = model.day, let rec = model.recommendation {
                WhyView(day: day, recommendation: rec)
            }
        }
    }

    private var percent: Int? {
        switch signal {
        case .recovery: return model.recoveryPercent
        case .sleep:    return model.sleepPercent
        case .strain:   return model.strainPercent(context: context)
        }
    }

    // MARK: - The two figures

    @ViewBuilder
    private var figures: some View {
        switch signal {
        case .recovery:
            metricCard(.hrv, symbol: "waveform.path.ecg", label: "Resting HRV")
            metricCard(.restingHeartRate, symbol: "heart", label: "Resting HR")

        case .sleep:
            StatCard(symbol: "bed.double", label: "Duration",
                     value: model.latestSleepHours.map {
                         $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                     unit: "h")
            StatCard(symbol: "hourglass", label: "Debt",
                     value: model.reading(.sleepDebt).map {
                         $0.value.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                     unit: "h")

        case .strain:
            StatCard(symbol: "scalemass", label: "Volume, 7d",
                     value: weeklyVolume > 0 ? formattedVolume : "—",
                     unit: weeklyVolume > 0 ? "lb" : nil)
            StatCard(symbol: "chart.line.uptrend.xyaxis", label: "Acute : chronic",
                     value: model.acwr.map {
                         $0.formatted(.number.precision(.fractionLength(2))) } ?? "—")
        }
    }

    @ViewBuilder
    private func metricCard(_ kind: MetricKind, symbol: String, label: String) -> some View {
        if let reading = model.reading(kind) {
            StatCard(symbol: symbol, label: label,
                     value: reading.value.formatted(.number.precision(.fractionLength(1))),
                     unit: reading.kind.unit,
                     trend: reading.zScore * kind.polarity >= 0 ? .up : .down)
        } else {
            StatCard(symbol: symbol, label: label, value: "—")
        }
    }

    private var weeklyVolume: Double {
        model.recentVolume(days: StrainEngine.chronicDays, context: context)
            .suffix(StrainEngine.acuteDays).reduce(0, +)
    }

    private var formattedVolume: String {
        weeklyVolume >= 10_000
            ? (weeklyVolume / 1000).formatted(.number.precision(.fractionLength(1))) + "k"
            : weeklyVolume.formatted(.number.precision(.fractionLength(0)))
    }

    // MARK: - Coaching, kept short

    private var coaching: String {
        switch signal {
        case .recovery:
            guard let reading = model.reading(.hrv) else { return "Still building your baseline." }
            let value = reading.value.formatted(.number.precision(.fractionLength(1)))
            let baseline = reading.baseline.formatted(.number.precision(.fractionLength(1)))
            let direction = reading.zScore < 0 ? "below" : "above"
            return "Your resting HRV (\(value) ms) is \(direction) its average of \(baseline) ms."

        case .sleep:
            guard let hours = model.latestSleepHours else { return "No sleep recorded last night." }
            let gap = DayAssembler.sleepNeedHours - hours
            return gap > 0.25
                ? "You were \(gap.formatted(.number.precision(.fractionLength(1)))) h short of your "
                  + "\(Int(DayAssembler.sleepNeedHours)) h target."
                : "You met your \(Int(DayAssembler.sleepNeedHours)) h target last night."

        case .strain:
            guard let acwr = model.acwr else { return "Needs more sessions." }
            return acwr > ReadinessEngine.acwrGate
                ? "This week is above your four-week average."
                : "Steady against your four-week average."
        }
    }

    // MARK: - Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline").sectionHeading()
            switch signal {
            case .sleep, .recovery:
                if let hours = model.latestSleepHours {
                    TimelineRow(symbol: "moon.stars.fill",
                                badge: model.sleepPercent.map(String.init),
                                title: "Primary sleep",
                                subtitle: "\(hours.formatted(.number.precision(.fractionLength(1)))) h recorded",
                                tint: Tokens.sleepLow)
                } else {
                    emptyTimeline("No sleep recorded")
                }
            case .strain:
                if todaysSessions.isEmpty {
                    emptyTimeline("No activities")
                } else {
                    ForEach(todaysSessions) { session in
                        TimelineRow(symbol: "figure.strengthtraining.traditional",
                                    badge: nil,
                                    title: session.templateName,
                                    subtitle: "\(Int(session.load.volumeLoad)) lb volume",
                                    tint: Tokens.strainLow)
                    }
                }
            }
        }
    }

    private var todaysSessions: [WorkoutSession] {
        sessions.filter { Calendar.current.isDateInToday($0.date) }
    }

    private func emptyTimeline(_ message: String) -> some View {
        Text(message)
            .font(.system(size: 15)).foregroundStyle(Tokens.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }

    // MARK: - Trends

    private var trends: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trends").sectionHeading()
            Group {
                switch signal {
                case .recovery:
                    Sparkline(values: model.compositeHistory(), tint: Tokens.recoveryHigh)
                        .frame(height: 96)
                case .sleep:
                    Sparkline(values: model.sleepHoursSeries(), tint: Tokens.sleepLow)
                        .frame(height: 96)
                case .strain:
                    let volumes = model.recentVolume(days: 14, context: context)
                    if volumes.allSatisfy({ $0 == 0 }) {
                        Text("No sessions yet")
                            .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                            .frame(height: 96)
                    } else {
                        Chart(Array(volumes.enumerated()), id: \.offset) { index, value in
                            BarMark(x: .value("Day", index), y: .value("Volume", value))
                                .foregroundStyle(Tokens.strainLow.opacity(0.85))
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 96)
                    }
                }
            }
            .bevelCard(padding: 14)
        }
    }
}
