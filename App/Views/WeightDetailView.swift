import SwiftUI
import SwiftData
import Charts

/// Weight in full, built on the same bones as a signal's screen: a hero at the top, two
/// figures under it, then the timeline of what it is made of.
///
/// It is not a signal, so it has no ring and no sky. Weight is a measurement somebody
/// takes rather than a score the app computes, and drawing a percentage ring around it
/// would be inventing a verdict. The hero is the line itself, which is the thing being
/// asked about.
struct WeightDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query(sort: \WeightLog.date, order: .reverse) private var logs: [WeightLog]

    @State private var loggingWeight = false
    @State private var range = Range.month

    enum Range: String, CaseIterable, Identifiable {
        case month = "28 days", quarter = "90 days", all = "All"
        var id: Self { self }
        var days: Int? {
            switch self {
            case .month: return 28
            case .quarter: return 90
            case .all: return nil
            }
        }
    }

    private var metric: Bool { model.onboarding.unitsAreMetric }
    private var unit: String { metric ? "kg" : "lb" }

    /// Every weigh-in the app knows about, from Health and from the logs, one a day.
    private var readings: [WeightTrend.Reading] {
        let fromHealth = model.series.compactMap { day in
            day.bodyMassKg.map { WeightTrend.Reading(date: day.date, kilograms: $0) }
        }
        let fromLogs = logs.map { WeightTrend.Reading(date: $0.date, kilograms: $0.kilograms) }
        return WeightTrend.daily(fromHealth + fromLogs)
    }

    private var charted: [WeightTrend.Reading] {
        guard let days = range.days else { return readings }
        return WeightTrend.window(readings, days: days)
    }

    private var change: WeightTrend.Change? { WeightTrend.latestChange(in: readings) }

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    HStack(spacing: Tokens.cardGap) { figures }
                    timeline
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.bottom, 16)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Weight")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Tokens.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { Haptics.light(); loggingWeight = true } label: {
                    Image(systemName: "plus").font(.system(size: 16, weight: .semibold))
                }
                .tint(Tokens.textPrimary)
                .accessibilityLabel("Log a weigh-in")
            }
        }
        .sheet(isPresented: $loggingWeight) { WeightLogView { _ in } }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let latest = readings.last {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(BodyMass.display(kilograms: latest.kilograms, metric: metric),
                         format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 44, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(Tokens.textPrimary)
                    Text(unit).font(.title3).foregroundStyle(Tokens.textSecondary)
                    Spacer()
                    Text(latest.date, format: .dateTime.month(.abbreviated).day())
                        .font(.subheadline).foregroundStyle(Tokens.textSecondary)
                }
                if charted.count > 1 {
                    chart
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } else {
                    // One reading is a number, not a trend, and saying so is better than
                    // drawing a line through a single point.
                    Text("One weigh-in so far. The line starts at two.")
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.textSecondary)
                }
            } else {
                EmptyStateView(message: "No weigh-ins yet. Add one and this fills in.") {
                    ListCard {
                        AccessoryRow(symbol: "plus", label: "Log a weigh-in") {
                            loggingWeight = true
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
    }

    private var chart: some View {
        Chart(charted, id: \.date) { reading in
            // Bounded at the bottom of the scale, not at zero. An area given only a y
            // value fills down to nought, which on a scale that starts at 182 is a long
            // way below the plot: the fill escaped the chart and painted a blue band
            // down the rest of the screen, over the timeline and past the tab bar.
            AreaMark(x: .value("Day", reading.date),
                     yStart: .value(unit, domain.lowerBound),
                     yEnd: .value(unit, BodyMass.display(kilograms: reading.kilograms, metric: metric)))
                .foregroundStyle(LinearGradient(colors: [Tokens.jettTint.opacity(0.22), .clear],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Day", reading.date),
                     y: .value(unit, BodyMass.display(kilograms: reading.kilograms, metric: metric)))
                .foregroundStyle(Tokens.jettTint)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.monotone)
        }
        // The domain is computed rather than left automatic. `includesZero: false` is a
        // hint Charts is free to ignore, and it did: the first render ran 0 to 200 and
        // drew two weeks of weight as a flat line pinned to the top of the card.
        .chartYScale(domain: domain)
        .chartYAxis { AxisMarks(position: .trailing) }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) }
        .frame(height: 170)
    }

    /// A window around the readings rather than around zero.
    ///
    /// Padded by a fixed amount rather than a share of the range, and never allowed to
    /// be narrower than a few units: a scale fitted tightly to two readings 200g apart
    /// magnifies a trip to the bathroom into a cliff, which is the opposite mistake to
    /// the flat line and reads as alarming rather than as nothing.
    private var domain: ClosedRange<Double> {
        let values = charted.map { BodyMass.display(kilograms: $0.kilograms, metric: metric) }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let span = metric ? 2.0 : 4.0
        let padding = max(span / 2, (high - low) * 0.25)
        return (low - padding)...(high + padding)
    }

    // MARK: - The two figures

    @ViewBuilder
    private var figures: some View {
        if let change {
            StatCard(symbol: change.isDown ? "arrow.down.right" : "arrow.up.right",
                     label: "Since \(change.from.formatted(.dateTime.month(.abbreviated).day()))",
                     value: abs(BodyMass.display(kilograms: change.kilograms, metric: metric))
                         .formatted(.number.precision(.fractionLength(1))),
                     unit: unit,
                     trend: change.isDown ? .down : .up,
                     // Direction is not news on its own. Down is the good news for
                     // somebody losing fat and the bad news for somebody bulking, so the
                     // colour follows what they told us they are here for.
                     trendFavourable: change.isDown == wantsToLose)
        } else {
            StatCard(symbol: "arrow.left.arrow.right", label: "Since last time", value: "–")
        }
        StatCard(symbol: "scalemass", label: "Weigh-ins", value: "\(readings.count)")
    }

    private var wantsToLose: Bool {
        model.onboarding.selectedGoals.contains(.loseFat)
    }

    // MARK: - Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Timeline").sectionHeading()
            if readings.isEmpty {
                Text("No weigh-ins recorded")
                    .font(.system(size: 15)).foregroundStyle(Tokens.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ForEach(Array(readings.reversed().prefix(30)), id: \.date) { reading in
                    TimelineRow(symbol: "scalemass",
                                badge: nil,
                                title: BodyMass.display(kilograms: reading.kilograms, metric: metric)
                                    .formatted(.number.precision(.fractionLength(1))) + " \(unit)",
                                subtitle: reading.date.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                                tint: Tokens.jettTint)
                }
            }
        }
    }
}
