import SwiftUI
import SwiftData
import Charts

/// Relationships over time, not a wall of charts. Each one exists to answer a question
/// the dashboard raises but cannot settle in a single day.
struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @Query(sort: \RecommendationRow.date, order: .reverse) private var recommendations: [RecommendationRow]

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    readinessTrend
                    loadTrend
                    sleepAgainstVolume
                    feedbackLoop
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.vertical, 8)
                .padding(.bottom, 88)
            }
        }
        .navigationTitle("Trends")
    }

    private var readinessTrend: some View {
        let history = model.compositeHistory(days: 30)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Recovery, last 30 days").sectionHeader()
            if history.count < 2 {
                Text("Not enough history yet.").font(.subheadline)
                    .foregroundStyle(Tokens.textSecondary).card()
            } else {
                Chart(Array(history.enumerated()), id: \.offset) { index, value in
                    AreaMark(x: .value("Day", index), y: .value("SD", value))
                        .foregroundStyle(Tokens.accent.opacity(0.14))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", index), y: .value("SD", value))
                        .foregroundStyle(Tokens.accent)
                        .interpolationMethod(.monotone)
                    RuleMark(y: .value("Baseline", 0))
                        .foregroundStyle(Tokens.hairline)
                        .lineStyle(StrokeStyle(dash: [3, 3]))
                }
                .chartXAxis(.hidden)
                .frame(height: 150)
                .card()
                Text("Zero is your own baseline. The line is standard deviations from it.")
                    .qualifier().padding(.horizontal, 4)
            }
        }
    }

    private var loadTrend: some View {
        let volumes = model.recentVolume(days: 28, context: context)
        return VStack(alignment: .leading, spacing: 10) {
            Text("Training volume, last 28 days").sectionHeader()
            if volumes.allSatisfy({ $0 == 0 }) {
                Text("Log a session and this fills in.").font(.subheadline)
                    .foregroundStyle(Tokens.textSecondary).card()
            } else {
                Chart(Array(volumes.enumerated()), id: \.offset) { index, value in
                    BarMark(x: .value("Day", index), y: .value("Volume", value))
                        .foregroundStyle(Tokens.accent.opacity(0.75))
                }
                .chartXAxis(.hidden)
                .frame(height: 130)
                .card()
                if let acwr = model.acwr {
                    Text("Acute against chronic load: "
                         + acwr.formatted(.number.precision(.fractionLength(2)))
                         + (acwr > ReadinessEngine.acwrGate
                            ? " — climbing faster than your month-long average."
                            : " — in the steady range."))
                        .qualifier().padding(.horizontal, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var sleepAgainstVolume: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sleep against training volume").sectionHeader()
            if points.count < 3 {
                Text("A few more logged sessions and this becomes readable.")
                    .font(.subheadline).foregroundStyle(Tokens.textSecondary).card()
            } else {
                Chart(points, id: \.date) { point in
                    PointMark(x: .value("Sleep, h", point.sleep),
                              y: .value("Volume, lb", point.volume))
                        .foregroundStyle(Tokens.accent)
                }
                .frame(height: 170)
                .card()
                if let insight = model.recentInsight {
                    Text(insight).qualifier().padding(.horizontal, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private struct Point { let date: Date; let sleep: Double; let volume: Double }

    private var points: [Point] {
        let calendar = Calendar.current
        let sleepSeries = model.sleepHoursSeries(days: 180)
        guard !sleepSeries.isEmpty else { return [] }
        return sessions.compactMap { session in
            guard let sleep = model.sleepHours(on: session.date) else { return nil }
            return Point(date: calendar.startOfDay(for: session.date),
                         sleep: sleep, volume: session.load.volumeLoad)
        }
    }

    /// Did the app's calls survive contact with the user? Without this the product can
    /// never find out whether it was any good.
    private var feedbackLoop: some View {
        let answered = recommendations.filter { $0.response != nil }
        return VStack(alignment: .leading, spacing: 10) {
            Text("Your responses").sectionHeader()
            if answered.isEmpty {
                Text("When you accept or override a recommendation, it lands here.")
                    .font(.subheadline).foregroundStyle(Tokens.textSecondary).card()
            } else {
                VStack(spacing: 0) {
                    ForEach(answered.prefix(10)) { row in
                        HStack {
                            Text(row.date, format: .dateTime.month(.abbreviated).day())
                                .font(.subheadline).monospacedDigit()
                                .foregroundStyle(Tokens.textPrimary)
                            Text(Copy.headline(for: row.state))
                                .font(.subheadline).foregroundStyle(Tokens.textSecondary)
                            Spacer()
                            Text(row.response?.rawValue.capitalized ?? "")
                                .font(.footnote).foregroundStyle(Tokens.textSecondary)
                        }
                        .padding(.vertical, 8)
                        if row.id != answered.prefix(10).last?.id {
                            Divider().overlay(Tokens.hairline)
                        }
                    }
                }
                .card()
            }
        }
    }
}
