import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @State private var showingCheckIn = false
    @State private var showingAdjust = false

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .sheet(isPresented: $showingCheckIn) { CheckInView() }
        .sheet(isPresented: $showingAdjust) { AdjustSessionView() }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 5) {
                Text("Today, ") + Text(Date(), format: .dateTime.month(.wide).day())
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.textSecondary)
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Tokens.textPrimary)
            Spacer()
            Circle()
                .fill(Tokens.sleepLow.opacity(0.18))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "person.fill")
                    .font(.system(size: 14)).foregroundStyle(Tokens.sleepLow))
        }
        .padding(.horizontal, Tokens.screenMargin)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background(Tokens.canvas)
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
            VStack(alignment: .leading, spacing: 24) {
                summaryCard
                session
                healthMonitor
            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.top, 2)
            .padding(.bottom, 96)
        }
    }

    // MARK: - Rings and coaching, one card

    private var summaryCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ringCell(.strain, percent: model.strainPercent(context: context))
                cellDivider
                ringCell(.recovery, percent: model.recoveryPercent)
                cellDivider
                ringCell(.sleep, percent: model.sleepPercent)
            }
            .padding(.vertical, 14)

            Divider().overlay(Tokens.hairline)

            if let rec = model.recommendation, let day = model.day {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Coaching").microLabel()
                    Text(Copy.call(for: rec, gate: day.readiness.gateApplied))
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)

                Divider().overlay(Tokens.hairline)

                Button { showingCheckIn = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: model.todayCheckIn == nil
                              ? "sparkles" : "checkmark.circle.fill")
                            .font(.system(size: 13))
                        Text(model.todayCheckIn == nil ? "Morning check-in" : "Check-in saved")
                            .font(.system(size: 15))
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 13))
                    }
                    .foregroundStyle(Tokens.textPrimary)
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.cardRadius,
                                                         style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
    }

    private var cellDivider: some View {
        Rectangle().fill(Tokens.hairline).frame(width: 1).padding(.vertical, 2)
    }

    private func ringCell(_ signal: Signal, percent: Int?) -> some View {
        NavigationLink {
            SignalDetailView(signal: signal)
        } label: {
            VStack(spacing: 9) {
                RingGauge(signal: signal, percent: percent, lineWidth: 7.5, figureSize: 20)
                    .frame(width: 70, height: 70)
                Text(signal.title)
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session

    @ViewBuilder
    private var session: some View {
        let templates = (try? context.fetch(
            FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\WorkoutTemplate.order)]))) ?? []
        if let planned = model.plannedToday(templates: templates), let rec = model.recommendation {
            VStack(alignment: .leading, spacing: 12) {
                Text("Today's session").sectionHeading()
                PlannedSessionCard(template: planned, recommendation: rec)
                Button { showingAdjust = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 13))
                        Text("Adjust session").font(.system(size: 15))
                        Spacer()
                        Image(systemName: "arrow.right").font(.system(size: 13))
                    }
                    .foregroundStyle(Tokens.textPrimary)
                    .bevelCard(padding: 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Health monitor

    private var healthMonitor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Monitor").sectionHeading()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Tokens.cardGap),
                                GridItem(.flexible(), spacing: Tokens.cardGap)],
                      spacing: Tokens.cardGap) {
                statCard(.respiratoryRate, symbol: "lungs", label: "RR")
                statCard(.restingHeartRate, symbol: "heart", label: "RHR")
                statCard(.hrv, symbol: "waveform.path.ecg", label: "HRV")
                statCard(.bloodOxygen, symbol: "drop", label: "SpO₂")
            }
        }
    }

    @ViewBuilder
    private func statCard(_ kind: MetricKind, symbol: String, label: String) -> some View {
        if let reading = model.reading(kind) {
            StatCard(symbol: symbol, label: label,
                     value: reading.value.formatted(.number.precision(.fractionLength(1))),
                     unit: reading.kind.unit,
                     trend: reading.zScore * kind.polarity >= 0 ? .up : .down)
        }
    }
}
