import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(GymPresence.self) private var gym
    @Environment(\.modelContext) private var context

    @State private var showingCheckIn = false
    @State private var pickingProgram = false
    @State private var showingAdjust = false
    @State private var showingWhy = false
    @State private var activeSession: WorkoutSession?
    @State private var loggingWeight = false
    @State private var loggingMeal = false
    @State private var editingTemplate: WorkoutTemplate?
    @State private var savedMessage: String?
    @State private var showSaved = false

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            content
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .sheet(isPresented: $showingCheckIn) { CheckInView() }
        .sheet(isPresented: $pickingProgram) {
            NavigationStack { ProgramSetupView { model.selectToday($0); pickingProgram = false } }
        }
        .sheet(item: $activeSession) { LiveWorkoutView(session: $0) }
        .sheet(isPresented: $loggingWeight, onDismiss: showSaveResult) { WeightLogView { saved($0) } }
        .sheet(isPresented: $loggingMeal, onDismiss: showSaveResult) { MealLogView { saved($0) } }
        .sheet(item: $editingTemplate) { template in
            TemplateEditorView(template: template) { model.selectToday($0); editingTemplate = nil }
        }
        .alert("Saved", isPresented: $showSaved) { Button("OK", role: .cancel) { savedMessage = nil } } message: { Text(savedMessage ?? "") }
        .sheet(isPresented: $showingAdjust) { AdjustSessionView() }
        .sheet(isPresented: $showingWhy) {
            if let day = model.day, let rec = model.recommendation {
                WhyView(day: day, recommendation: rec)
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 5) {
                Text("Today, ") + Text(Date(), format: .dateTime.month(.wide).day())
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Tokens.textPrimary)
            Spacer()
            // The profile button, not a sleep affordance. It was purple because purple
            // was to hand, which is exactly the decoration the icon rule exists to stop.
            Circle()
                .fill(Tokens.textPrimary.opacity(0.07))
                .frame(width: 32, height: 32)
                .overlay(Image(systemName: "person.fill")
                    .font(.system(size: 14)).foregroundStyle(Tokens.textPrimary))
        }
        .padding(.horizontal, Tokens.screenMargin)
        .padding(.top, 6)
        .padding(.bottom, 11)
        .background(Tokens.canvas)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Tokens.hairline).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().controlSize(.large).tint(Tokens.accent)
        case .needsOnboarding:
            // RootView shows onboarding over the whole app; this is only ever a frame
            // in between.
            Color.clear
        case .failed:
            dashboard
        case .ready:
            dashboard
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Above everything, because it is a question and it is rare. It
                // disappears the moment it is answered and never comes back for that
                // place.
                if let place = gym.placeToConfirm {
                    GymConfirmCard(visit: place,
                                   onConfirm: { gym.confirmGym(named: $0, at: place) },
                                   onDecline: { gym.declineGym(at: place) })
                }
                summaryCard
                checkInPrompt
                if let error = model.healthReadError { Text("Health couldn't refresh. \(error)").font(.footnote).foregroundStyle(.secondary) }
                // The screen below the fold is composed from the goal, not fixed:
                // someone here to sleep better does not open on a back squat.
                ForEach(model.homeBlocks, id: \.self) { block in
                    view(for: block)
                }
                insight
            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.top, 2)
            .padding(.bottom, 100)
        }
        .accessibilityIdentifier("today-overview")
        .refreshable { await model.refresh() }
    }

    private func saved(_ message: String) { savedMessage = message }
    private func showSaveResult() { if savedMessage != nil { showSaved = true } }

    // MARK: - Rings and coaching, one card

    /// Two surfaces, not one card with a rule through it: the rings sit on top of the
    /// coaching card, their rounded bottom edge and shadow doing the separating.
    private var summaryCard: some View {
        VStack(spacing: -18) {
            HStack(spacing: 0) {
                ringCell(.strain, percent: model.strainPercent(context: context))
                cellDivider
                ringCell(.recovery, percent: model.recoveryPercent)
                cellDivider
                ringCell(.sleep, percent: model.sleepPercent)
            }
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(Tokens.surface,
                        in: RoundedRectangle(cornerRadius: Tokens.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 4)
            .zIndex(1)

            if let rec = model.recommendation, let day = model.day {
                Button { showingWhy = true } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Coaching").microLabel()
                        Text(Copy.call(for: rec, gate: day.readiness.gateApplied,
                                       hasSession: model.hasProgram))
                            .font(.system(size: 15))
                            .foregroundStyle(Tokens.textPrimary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let note = Copy.confidenceNote(rec.confidence, days: day.daysOfHistory) {
                            Text(note)
                                .font(.system(size: 13))
                                .foregroundStyle(Tokens.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    // Extra head room so the copy clears the card resting on top of it.
                    .padding(.top, 31)
                    .padding(.bottom, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityHint("Shows how this was calculated")
                .frame(maxWidth: .infinity)
                .background(Tokens.surface,
                            in: RoundedRectangle(cornerRadius: Tokens.cardRadius,
                                                 style: .continuous))
                .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
            }
        }
    }

    private var cellDivider: some View {
        Rectangle().fill(Tokens.hairline).frame(width: 1).padding(.vertical, 2)
    }

    private func ringCell(_ signal: Signal, percent: Int?) -> some View {
        NavigationLink {
            SignalDetailView(signal: signal)
        } label: {
            VStack(spacing: 9) {
                RingGauge(signal: signal, percent: percent, lineWidth: 9, figureSize: 23)
                    .frame(width: 78, height: 78)
                Text(signal.title)
                    .font(.system(size: 13))
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
        if let planned = model.plannedToday(templates: templates) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Today's session").sectionHeading()
                PlannedSessionCard(template: planned, recommendation: model.recommendation,
                    onChange: { pickingProgram = true }, onEdit: { editingTemplate = planned },
                    onStart: { activeSession = WorkoutSession.today(in: context, named: planned.name) })
            }
        }
    }

    // MARK: - Check-in

    /// Asks once, then gets out of the way. A saved check-in is something the user
    /// already knows; it does not need a row saying so.
    @ViewBuilder
    private var checkInPrompt: some View {
        if model.todayCheckIn == nil {
            Button { showingCheckIn = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "sun.horizon.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.accent)
                    Text("How are you feeling?")
                        .font(.body.weight(.semibold)).foregroundStyle(Tokens.textPrimary)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.textSecondary)
                }
                .padding(18).frame(minHeight: 62)
                .background(Tokens.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: Tokens.cardRadius))
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: - Insight

    /// One pattern, or nothing at all.
    @ViewBuilder
    private var insight: some View {
        if let line = model.recentInsight {
            VStack(alignment: .leading, spacing: 12) {
                Text("Pattern").sectionHeading()
                Text(line)
                    .font(.system(size: 15))
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .bevelCard()
            }
        }
    }

    // MARK: - Goal-driven blocks

    @ViewBuilder
    private func view(for block: HomeBlock) -> some View {
        let today = model.series.last { Calendar.current.isDateInToday($0.date) }
        switch block {
        case .session:
            session
        case .programPrompt:
            programPrompt
        case .nutrition:
            NutritionCard(calories: today?.dietaryEnergyKcal, protein: today?.proteinGrams,
                carbs: today?.carbohydrateGrams, fat: today?.fatGrams, onLog: { loggingMeal = true })
        case .weightTrend:
            WeightTrendCard(latest: model.latestWeight, series: model.series.compactMap(\.bodyMassKg),
                metric: model.onboarding.unitsAreMetric, onLog: { loggingWeight = true })
        case .sleepQuality:
            SleepQualityCard(night: today?.sleep, summary: model.sleepScore.summary)
        case .movement:
            MovementCard(activeEnergy: today?.activeEnergyKcal, steps: today?.steps, exerciseMinutes: today?.exerciseMinutes)
        case .healthMonitor:
            healthMonitor
        }
    }

    private var programPrompt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training").sectionHeading()
            AccessoryRow(symbol: "square.stack.3d.up", label: "Build your training plan") {
                pickingProgram = true
            }
        }
    }

    // MARK: - Health monitor

    private var healthMonitor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health Monitor").sectionHeading()
            VStack(spacing: 0) {
                metricRow(.respiratoryRate, symbol: "lungs", label: "Breathing rate")
                Divider().padding(.leading, 44)
                metricRow(.restingHeartRate, symbol: "heart", label: "Resting heart rate")
                Divider().padding(.leading, 44)
                metricRow(.hrv, symbol: "waveform.path.ecg", label: "Heart rate variability")
                Divider().padding(.leading, 44)
                metricRow(.bloodOxygen, symbol: "drop", label: "Blood oxygen")
            }.bevelCard(padding: 16)
        }
    }

    private func metricRow(_ kind: MetricKind, symbol: String, label: String) -> some View {
        let raw = model.series.last { Calendar.current.isDateInToday($0.date) }?.value(for: kind)
        let reading = model.reading(kind)
        return HStack(spacing: 12) {
            Image(systemName: symbol).font(.body).foregroundStyle(Tokens.textSecondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) { Text(label).font(.subheadline); InfoButton(kind) }
                Text(reading.map { Copy.position($0.zScore) } ?? (raw == nil ? "No reading today" : "Learning your usual range"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let value = raw {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(value, format: .number.precision(.fractionLength(1))).font(.headline).monospacedDigit()
                    Text(kind.unit).font(.caption2).foregroundStyle(.secondary)
                }
            } else { Text("—").foregroundStyle(.secondary) }
        }.padding(.vertical, 12)
    }
}
