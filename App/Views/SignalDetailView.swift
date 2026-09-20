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
            if signal == .recovery, let day = model.day, let rec = model.recommendation {
                WhyView(day: day, recommendation: rec)
            } else {
                calculationInfo
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
            StatCard(symbol: "moon.zzz", label: "Continuity",
                     value: model.sleepScore.contributor("continuity")?.value
                         .map { String(Int($0.rounded())) } ?? "—",
                     unit: model.sleepScore.contributor("continuity") == nil ? nil : "%")

        case .strain:
            StatCard(symbol: "flame", label: model.dailyStrain?.metric.label ?? "Activity today",
                     value: model.dailyStrain.map {
                         $0.value.formatted(.number.precision(.fractionLength(0))) } ?? "—",
                     unit: model.dailyStrain?.metric.unit)
            StatCard(symbol: "calendar", label: "Prior recorded days",
                     value: model.dailyStrain.map { String($0.baselineDays) } ?? "—")
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

    private var calculationInfo: some View {
        NavigationStack {
            List {
                Section("What is recorded") {
                    Text(coaching)
                }
                switch signal {
                case .sleep:
                    Section("How the estimate works") {
                        Text("Duration target coverage is multiplied by recorded sleep continuity. Continuity is time asleep divided by a credible in-bed window, or by continuously recorded time between the first and last sleep stages.")
                        Text("With at least 7 prior sleep schedules in 28 days, bedtime and wake-time consistency can reduce the result by up to 10%. A typical shift of 2 hours applies the full adjustment. These are product choices, not clinical thresholds.")
                        Text("Source: sleep records shared through Apple Health. Missing intervals and conflicting awake/asleep records are not treated as good sleep. REM and deep-sleep amounts do not receive invented ideal targets.")
                    }
                case .strain:
                    Section("What the number means") {
                        Text("The ring compares one recorded activity measure with at least 7 prior observed days in the last 28 days. A value of 50 is around your usual day; 100 is among your highest recorded days. It is not a maximum effort limit or a physiological strain measure.")
                        Text("Today's activity is still accumulating. The comparison uses prior daily totals, so it will usually be lower early in the day.")
                        Text("Source: Apple Health. Active energy is preferred, followed by exercise time, steps, workout energy, then workout time. The selected source is shown above. Workout calories are never added to active calories, which already include exercise.")
                        Text("A missing day is excluded, not entered as zero. A recorded zero does not prove the device tracked the whole day. In-app lifting volume and acute-to-chronic load remain separate from this daily activity comparison.")
                    }
                case .recovery:
                    Section("Readiness") {
                        Text("A readiness explanation appears when today's measurements and recommendation are available.")
                    }
                }
            }
            .navigationTitle("About \(signal.title.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
            return model.sleepScore.summary

        case .strain:
            return model.strainScore(context: context).summary
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
                if let activity = model.dailyStrain {
                    TimelineRow(symbol: "figure.walk", badge: nil,
                                title: activity.metric.label,
                                subtitle: "\(activity.value.formatted(.number.precision(.fractionLength(0)))) \(activity.metric.unit) recorded in Health today",
                                tint: Tokens.strainLow)
                }
                if todaysSessions.isEmpty && model.dailyStrain == nil {
                    emptyTimeline("No recorded activities today")
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

    private var strainObservations: [(date: Date, value: Double)] {
        guard let metric = model.dailyStrain?.metric,
              let cutoff = Calendar.current.date(byAdding: .day, value: -13,
                                                 to: Calendar.current.startOfDay(for: Date())) else { return [] }
        return model.series.compactMap { day in
            guard day.date >= cutoff, day.date <= Date() else { return nil }
            let value: Double?
            switch metric {
            case .activeEnergy: value = day.activeEnergyKcal
            case .exerciseMinutes: value = day.exerciseMinutes
            case .steps: value = day.steps
            case .workoutEnergy: value = day.workoutEnergyKcal
            case .workoutMinutes: value = day.workoutMinutes
            }
            guard let value, value.isFinite, value >= 0 else { return nil }
            return (date: day.date, value: value)
        }
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
                    let observations = strainObservations
                    if observations.isEmpty {
                        Text("No activity history for this measure")
                            .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                            .frame(height: 96)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(model.dailyStrain?.metric.label ?? "Activity") · \(model.dailyStrain?.metric.unit ?? "")")
                                .font(.caption).foregroundStyle(Tokens.textSecondary)
                            Chart(observations, id: \.date) { observation in
                                BarMark(x: .value("Day", observation.date, unit: .day),
                                        y: .value("Recorded activity", observation.value))
                                    .foregroundStyle(Tokens.strainLow.opacity(0.85))
                            }
                            .chartXAxis(.hidden)
                            .frame(height: 96)
                        }
                    }
                }
            }
            .bevelCard(padding: 14)
        }
    }
}
