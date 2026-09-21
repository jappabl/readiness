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
                    HeroRing(signal: signal, percent: percent,
                             target: signal == .strain
                                 ? StrainScore.target(recovery: model.recoveryScore.value) : nil,
                             stages: SleepStages(score: score))
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                    // The ring draws the night's shape; without these it withholds the
                    // numbers that shape is made of.
                    if let stages = SleepStages(score: score) {
                        SleepStageKey(stages: stages, columns: 2)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 4)
                    }
                    HStack(spacing: Tokens.cardGap) { figures }
                    CoachCard(message: coaching,
                              accessory: (label: "View insights", symbol: "sparkles"),
                              action: { showingWhy = true })
                    timeline
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
                Button { Haptics.light(); showingWhy = true } label: {
                    Image(systemName: "info.circle").font(.system(size: 16))
                }
                .tint(Tokens.textPrimary)
                .accessibilityLabel("How this is calculated")
            }
        }
        .sheet(isPresented: $showingWhy) {
            InsightsView(score: score)
        }
    }

    private var score: SignalScore {
        switch signal {
        case .recovery: return model.recoveryScore
        case .sleep:    return model.sleepScore
        case .strain:   return model.strainScore(context: context)
        }
    }

    /// The ring still wants a 0...100, and strain is on its own scale.
    private var percent: Int? {
        guard let value = score.value else { return nil }
        return signal == .strain
            ? Int((value / StrainScore.scaleMax * 100).rounded())
            : Int(value.rounded())
    }

    // MARK: - The two figures

    @ViewBuilder
    private var figures: some View {
        switch signal {
        case .recovery:
            metricCard(.hrv, symbol: "waveform.path.ecg", label: "Resting HRV")
            metricCard(.restingHeartRate, symbol: "heart", label: "Resting HR")

        case .sleep:
            StatCard(symbol: "bed.double", label: "Time asleep",
                     value: model.latestSleepHours.map {
                         $0.formatted(.number.precision(.fractionLength(1))) } ?? "–",
                     unit: "h")
            StatCard(symbol: "target", label: "What you need",
                     value: score.contributor(SleepScore.durationContributorID)?.comparison
                         .map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "–",
                     unit: "h")

        case .strain:
            StatCard(symbol: "flame", label: model.dailyStrain?.metric.label ?? "Activity today",
                     value: model.dailyStrain.map {
                         $0.value.formatted(.number.precision(.fractionLength(0))) } ?? "–",
                     unit: model.dailyStrain?.metric.unit)
            StatCard(symbol: "calendar", label: "Prior recorded days",
                     value: model.dailyStrain.map { String($0.baselineDays) } ?? "–")
        }
    }

    @ViewBuilder
    private func metricCard(_ kind: MetricKind, symbol: String, label: String) -> some View {
        if let reading = model.reading(kind) {
            // The arrow points the way the *reading* moved; the colour says whether that
            // was good news. `trendFavourable` exists for exactly this and had no caller,
            // so it defaulted to true and every arrow on this screen was green: a resting
            // heart rate ten beats above baseline drew a green arrow here and a red one on
            // the two screens that show the same row.
            // The quantity this metric is scored on, so this screen and the insights grid
            // cannot point opposite ways about the same metric on the same morning.
            let favourable = reading.scoringZ * kind.polarity >= 0
            StatCard(symbol: symbol, label: label,
                     value: reading.scoringValue.formatted(.number.precision(.fractionLength(1))),
                     unit: reading.kind.unit,
                     trend: reading.scoringZ >= 0 ? .up : .down,
                     trendFavourable: favourable)
        } else {
            StatCard(symbol: symbol, label: label, value: "–")
        }
    }

    // MARK: - Coaching, kept short

    private var coaching: String {
        switch signal {
        case .recovery:
            guard let reading = model.reading(.hrv) else { return "Still building your baseline." }
            // The week, which is what HRV is scored on, not last night. This sentence and
            // the insights row behind the info button disagreed in sign on a fifth of
            // mornings, because one read the reading and the other read the trend.
            let value = reading.scoringValue.formatted(.number.precision(.fractionLength(1)))
            let baseline = reading.baseline.formatted(.number.precision(.fractionLength(1)))
            let direction = reading.scoringZ < 0 ? "below" : "above"
            return "Your resting HRV has averaged \(value) ms this week, \(direction) "
                 + "its usual \(baseline) ms."

        case .sleep, .strain:
            return score.summary
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
}
