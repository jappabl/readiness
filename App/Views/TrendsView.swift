import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
    @Query(sort: \RecommendationRow.date, order: .reverse) private var recommendations: [RecommendationRow]

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    recovery
                    volume
                    sleepAgainstVolume
                    responses
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.top, 4)
                .padding(.bottom, 96)
            }
        }
        .navigationTitle("Trends")
        .toolbarBackground(Tokens.canvas, for: .navigationBar)
    }

    private func section<Content: View>(_ title: String, footnote: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).sectionHeading()
            content().bevelCard(padding: 14)
            if let footnote {
                Text(footnote).font(.system(size: 13))
                    .foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }

    private var recovery: some View {
        let history = model.compositeHistory(days: 30)
        return section("Recovery", footnote: "Zero is your own baseline.") {
            if history.count < 2 {
                Text("Not enough history yet.")
                    .font(.system(size: 15)).foregroundStyle(Tokens.textSecondary)
            } else {
                Chart(Array(history.enumerated()), id: \.offset) { index, value in
                    AreaMark(x: .value("Day", index), y: .value("SD", value))
                        .foregroundStyle(LinearGradient(
                            colors: [Tokens.recoveryHigh.opacity(0.22), Tokens.recoveryHigh.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", index), y: .value("SD", value))
                        .foregroundStyle(Tokens.recoveryHigh)
                        .interpolationMethod(.monotone)
                    RuleMark(y: .value("Baseline", 0))
                        .foregroundStyle(Tokens.hairline)
                        .lineStyle(StrokeStyle(dash: [3, 3]))
                }
                .chartXAxis(.hidden)
                .frame(height: 150)
            }
        }
    }

    private var volume: some View {
        let volumes = model.recentVolume(days: 28, context: context)
        return section("Training volume",
                       footnote: model.acwr.map {
                           "Acute against chronic: "
                           + $0.formatted(.number.precision(.fractionLength(2)))
                           + ($0 > ReadinessEngine.acwrGate ? " — climbing fast." : " — steady.")
                       }) {
            if volumes.allSatisfy({ $0 == 0 }) {
                Text("Log a session and this fills in.")
                    .font(.system(size: 15)).foregroundStyle(Tokens.textSecondary)
            } else {
                Chart(Array(volumes.enumerated()), id: \.offset) { index, value in
                    BarMark(x: .value("Day", index), y: .value("Volume", value))
                        .foregroundStyle(Tokens.strainLow.opacity(0.85))
                        .cornerRadius(2)
                }
                .chartXAxis(.hidden)
                .frame(height: 130)
            }
        }
    }

    private var sleepAgainstVolume: some View {
        section("Sleep against volume", footnote: model.recentInsight) {
            if points.count < 3 {
                Text("A few more logged sessions and this becomes readable.")
                    .font(.system(size: 15)).foregroundStyle(Tokens.textSecondary)
            } else {
                Chart(points, id: \.date) { point in
                    PointMark(x: .value("Sleep, h", point.sleep),
                              y: .value("Volume, lb", point.volume))
                        .foregroundStyle(Tokens.sleepLow)
                }
                .frame(height: 165)
            }
        }
    }

    private struct Point { let date: Date; let sleep: Double; let volume: Double }

    private var points: [Point] {
        sessions.compactMap { session in
            guard let sleep = model.sleepHours(on: session.date) else { return nil }
            return Point(date: Calendar.current.startOfDay(for: session.date),
                         sleep: sleep, volume: session.load.volumeLoad)
        }
    }

    private var responses: some View {
        let answered = recommendations.filter { $0.response != nil }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Your responses").sectionHeading()
            if answered.isEmpty {
                Text("When you accept or override a call, it lands here.")
                    .font(.system(size: 15)).foregroundStyle(Tokens.textSecondary)
                    .bevelCard()
            } else {
                ListCard {
                    ForEach(Array(answered.prefix(10).enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                        FieldRow(label: Copy.headline(for: row.state)) {
                            HStack(spacing: 8) {
                                Text(row.response?.rawValue.capitalized ?? "")
                                Text(row.date, format: .dateTime.month(.abbreviated).day())
                                    .foregroundStyle(Tokens.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }
}
