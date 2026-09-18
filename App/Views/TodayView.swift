import SwiftUI
import SwiftData

/// Answers three questions, in order: how am I doing, why, and what should I do.
/// The rings give the glance; the coaching card carries the decision.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @State private var showingCheckIn = false
    @State private var showingWhy = false
    @State private var showingAdjust = false

    var body: some View {
        ZStack {
            SkyBackground(signal: .readiness).opacity(0.7)
            content
        }
        .sheet(isPresented: $showingCheckIn) { CheckInView() }
        .sheet(isPresented: $showingWhy) {
            if let day = model.day, let rec = model.recommendation {
                WhyView(day: day, recommendation: rec)
            }
        }
        .sheet(isPresented: $showingAdjust) { AdjustSessionView() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().controlSize(.large).tint(Tokens.accent)
        case .needsProgram:
            ProgramSetupView()
        case .failed(let message):
            ContentUnavailableView("Nothing to read yet", systemImage: "heart.text.square",
                                   description: Text(message))
        case .ready:
            dashboard
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dateLine
                rings
                if let rec = model.recommendation, let day = model.day {
                    CoachingCard(recommendation: rec, day: day,
                                 response: model.todayResponse,
                                 onAdjust: { showingAdjust = true },
                                 onWhy: { showingWhy = true },
                                 onCheckIn: { showingCheckIn = true },
                                 hasCheckIn: model.todayCheckIn != nil)
                }
                measurements
                plannedSession
                insight
            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.top, 4)
            .padding(.bottom, 92)
        }
    }

    private var dateLine: some View {
        Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Tokens.textSecondary)
    }

    /// The glance. Tapping any ring opens the full picture for that signal.
    private var rings: some View {
        HStack(spacing: 10) {
            ringLink(.readiness, percent: model.readinessPercent,
                     caption: percentileCaption)
            ringLink(.sleep, percent: model.sleepPercent,
                     caption: model.sleepPercent == nil ? "no data" : "of need")
            ringLink(.load, percent: model.loadPercent(context: context),
                     caption: model.loadPercent(context: context) == nil ? "few sessions" : "of usual")
        }
    }

    private var percentileCaption: String {
        guard let percent = model.readinessPercent else { return "calibrating" }
        switch percent {
        case 90...: return "top 10%"
        case ..<10: return "bottom 10%"
        default: return "percentile"
        }
    }

    private func ringLink(_ signal: Signal, percent: Int?, caption: String) -> some View {
        NavigationLink {
            SignalDetailView(signal: signal)
        } label: {
            RingGauge(signal: signal, percent: percent, caption: caption, lineWidth: 9)
                .padding(.vertical, 14)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .background(Tokens.surface,
                            in: RoundedRectangle(cornerRadius: Tokens.cardRadius))
        }
        .buttonStyle(.plain)
    }

    private var measurements: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Measurements").sectionHeader()
            VStack(spacing: 0) {
                ForEach(MetricKind.allCases, id: \.self) { kind in
                    if let reading = model.reading(kind) {
                        MeasurementRow(reading: reading)
                        if kind != MetricKind.allCases.last {
                            Divider().overlay(Tokens.hairline)
                        }
                    }
                }
            }
            .card()
        }
    }

    @ViewBuilder
    private var plannedSession: some View {
        let templates = (try? context.fetch(
            FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\WorkoutTemplate.order)]))) ?? []
        if let planned = model.plannedToday(templates: templates), let rec = model.recommendation {
            VStack(alignment: .leading, spacing: 10) {
                Text("Today's session").sectionHeader()
                PlannedSessionCard(template: planned, recommendation: rec)
            }
        }
    }

    @ViewBuilder
    private var insight: some View {
        if let line = model.recentInsight {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pattern").sectionHeader()
                Text(line).font(.subheadline).foregroundStyle(Tokens.textPrimary).card()
            }
        }
    }
}

// MARK: - The coaching card

struct CoachingCard: View {
    let recommendation: Recommendation
    let day: AssembledDay
    let response: RecommendationResponse?
    let onAdjust: () -> Void
    let onWhy: () -> Void
    let onCheckIn: () -> Void
    let hasCheckIn: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coaching").sectionHeader()

            Text(Copy.headline(for: recommendation.state))
                .font(.system(size: headlineSize, weight: .semibold))
                .foregroundStyle(Tokens.accent)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text(Copy.call(for: recommendation, gate: day.readiness.gateApplied))
                .font(.body)
                .foregroundStyle(Tokens.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if !recommendation.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(recommendation.evidence.prefix(3), id: \.kind) { contribution in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle().fill(Tokens.textTertiary)
                                .frame(width: 3, height: 3)
                                .offset(y: -3)
                            Text(Copy.describe(contribution))
                                .font(.subheadline)
                                .foregroundStyle(Tokens.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let note = Copy.confidenceNote(recommendation.confidence, days: day.daysOfHistory) {
                Text(note).qualifier().fixedSize(horizontal: false, vertical: true)
            }

            if let response {
                Label(responseLabel(response), systemImage: "checkmark.circle.fill")
                    .font(.footnote).foregroundStyle(Tokens.textSecondary)
            }

            actions
        }
        .card()
    }

    private func responseLabel(_ response: RecommendationResponse) -> String {
        switch response {
        case .accepted: return "You accepted this"
        case .modified: return "You modified this"
        case .rejected: return "You trained through it"
        }
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { buttons }
            VStack(alignment: .leading, spacing: 8) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button("Adjust session", action: onAdjust)
            .buttonStyle(.borderedProminent).tint(Tokens.accent)
            .foregroundStyle(Tokens.onAccent)
        Button("Ask why", action: onWhy).buttonStyle(.bordered).tint(Tokens.accent)
        Button(hasCheckIn ? "Check-in ✓" : "Check in", action: onCheckIn)
            .buttonStyle(.bordered).tint(Tokens.accent)
    }
}

// MARK: - Measurement row

struct MeasurementRow: View {
    let reading: MetricReading

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(reading.kind.displayName)
                .font(.subheadline).foregroundStyle(Tokens.textPrimary)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(reading.value, format: .number.precision(.fractionLength(1)))
                    .font(.subheadline).monospacedDigit().foregroundStyle(Tokens.textPrimary)
                Text(reading.kind.unit).qualifier()
                Text(deltaText)
                    .font(.footnote).monospacedDigit()
                    .foregroundStyle(isFavourable ? Tokens.positive : Tokens.negative)
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(reading.kind.displayName) "
            + "\(reading.value.formatted(.number.precision(.fractionLength(1)))) "
            + "\(reading.kind.unit), \(deltaText) from baseline")
    }

    private var deltaText: String {
        reading.zScore.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))
            + " SD"
    }

    private var isFavourable: Bool { reading.zScore * reading.kind.polarity >= 0 }
}
