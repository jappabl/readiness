import Foundation
import HealthKit
import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppModel {

    enum Phase {
        case loading
        case needsOnboarding
        case ready
        case failed(String)
    }

    var phase: Phase = .loading
    var day: AssembledDay?
    var recommendation: Recommendation?
    var todayCheckIn: CheckIn?
    var acwr: Double?
    var recentInsight: String?
    var seededSampleCount: Int?
    var goal: TrainingGoal?
    var hasProgram = false
    var onboarding = OnboardingAnswers()
    /// Separate from `goal`: the goal is stored the moment it is picked, but the flow
    /// runs on past it to the Health prompt and the baseline reveal.
    var onboardingFinished = false

    private(set) var hasOnboardingHealthData = false
    private(set) var healthProfile = HealthProfile()
    var effectiveHealthProfile: HealthProfile {
        healthProfile.fillingMissing(from: onboarding.healthDetails ?? HealthProfile())
    }
    var trainingLimitations: Set<PhysicalLimitation>? {
        guard let context,
              let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        else { return onboarding.limitations ?? [] }
        return PhysicalLimitation.from(profileText: profile.limitations)
    }
    var coachSharingAllowed = CoachSharing.isAllowed {
        didSet { CoachSharing.setAllowed(coachSharingAllowed) }
    }
    var pendingCoachMessage: String?
    var pendingOnboardingConversation: [CoachMessage] = []
    private var healthAuthorizationRequested = false
    private static let healthSkipKey = "health.connection.skipped"

    func skipHealthConnection() {
        UserDefaults.standard.set(true, forKey: Self.healthSkipKey)
        healthProfile = HealthProfile()
    }

    /// How many answers the free trial has spent. UserDefaults rather than the store:
    /// it is a counter, not a record, and it does not deserve a migration.
    var coachMessagesUsed: Int {
        get { UserDefaults.standard.integer(forKey: Self.coachUseKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.coachUseKey) }
    }
    private static let coachUseKey = "coach.messages.used"

    func recordCoachMessage() { coachMessagesUsed += 1 }

    /// Handed to the gym watcher so it can ask HealthKit whether a visit had exertion
    /// in it, without the watcher knowing anything about HealthKit.
    func workoutLookup() -> @Sendable (Date, Date) async -> Bool {
        let source = healthKit
        return { start, end in await source.hadWorkout(between: start, and: end) }
    }

    /// The burst bucket, persisted so quitting the app is not a way around it.
    private static let burstKey = "coach.burst"

    private var burstState: BurstLimiter.State {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.burstKey),
                  let decoded = try? JSONDecoder().decode(BurstLimiter.State.self, from: data)
            else { return BurstLimiter.State() }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: Self.burstKey)
            }
        }
    }

    /// Nil when the message may go, otherwise the seconds to wait.
    func burstDelay(now: Date = Date()) -> TimeInterval? {
        let decision = BurstLimiter.consume(burstState, now: now)
        burstState = decision.state
        return decision.allowed ? nil : decision.retryAfter
    }

    private(set) var series: [DailyPhysiology] = []
    private var healthSeries: [DailyPhysiology] = []
    private(set) var latestWeight: (date: Date, kilograms: Double)?
    private var healthWeight: (date: Date, kilograms: Double)?
    var healthReadError: String?
    private var selectedTemplateID: PersistentIdentifier? {
        didSet {
            if let selectedTemplateID, let data = try? JSONEncoder().encode(selectedTemplateID) {
                UserDefaults.standard.set(data, forKey: "training.today.template")
                UserDefaults.standard.set(Calendar.current.startOfDay(for: Date()), forKey: "training.today.date")
            }
        }
    }

    /// Retracts while the user is reading, returns when they stop or scroll back.

    /// How the user answered today's call. Stored so views react when it changes.
    var todayResponse: RecommendationResponse?

    /// A change the coach proposed and the user approved. Composed on top of the
    /// engine's own adjustments — the coach adds to the call, it does not replace it.
    var coachAdjustment: SessionAdjustment?

    private let healthKit = HealthKitSource()
    private var context: ModelContext?

    static let historyDays = 180

    func attach(_ context: ModelContext) {
        self.context = context
        if let date = UserDefaults.standard.object(forKey: "training.today.date") as? Date,
           Calendar.current.isDateInToday(date),
           let data = UserDefaults.standard.data(forKey: "training.today.template") {
            selectedTemplateID = try? JSONDecoder().decode(PersistentIdentifier.self, from: data)
        }
        mergeLocalLogs()
        goal = storedGoal(from: context)
        // A goal already on disk means onboarding ran in an earlier launch.
        onboardingFinished = goal != nil
        if let json = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.onboardingJSON,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(OnboardingAnswers.self, from: data) {
            onboarding = decoded
        }
        // Nothing is read from Health until the user has been told why. Asking for
        // six months of physiology before saying what the app is for is how a health
        // app gets declined on the first screen.
        if goal == nil { phase = .needsOnboarding }
        #if DEBUG
        // Replay the real flow on a simulator or device without resetting Health permissions.
        if ProcessInfo.processInfo.arguments.contains("--demo-onboarding") {
            goal = nil
            onboardingFinished = false
            phase = .needsOnboarding
        }
        // Straight to a populated app, for looking at the whole thing at once. Pairs
        // with --seed-health-fixture, which supplies the physiology.
        if ProcessInfo.processInfo.arguments.contains("--demo-today") {
            let profile = profileRow(in: context)
            if TrainingGoal(rawValue: profile.goal) == nil {
                profile.goal = TrainingGoal.buildMuscle.rawValue
                try? context.save()
            }
            goal = storedGoal(from: context)
            onboardingFinished = true
        }
        #endif
    }

    var needsOnboarding: Bool { goal == nil || !onboardingFinished }

    // MARK: - Load

    func refresh(seedSimulatorData: Bool = false, requestHealthAccess: Bool = false,
                 onAuthorized: (() -> Void)? = nil, onHealthRead: ((Bool) -> Void)? = nil) async {
        guard let context else { return }
        #if DEBUG && targetEnvironment(simulator)
        // Explicit QA fixture only. Ordinary onboarding never invents Health history.
        let seedSimulatorData = seedSimulatorData
            || ProcessInfo.processInfo.arguments.contains("--seed-health-fixture")
        #endif
        if case .ready = phase {} else { phase = .loading }
        todayCheckIn = fetchTodayCheckIn(from: context)
        acwr = computeACWR(from: context)
        let templates = (try? context.fetch(
            FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\.order)]))) ?? []
        hasProgram = !templates.isEmpty
        goal = storedGoal(from: context)
        #if DEBUG
        // A whole populated app, without HealthKit and therefore without a permission
        // sheet somebody has to tap. Seeding writes real samples and needs share
        // access; this just hands the model a series.
        if ProcessInfo.processInfo.arguments.contains("--demo-today") {
            healthSeries = DemoPhysiology.series()
            healthWeight = healthSeries.last.flatMap { day in
                day.bodyMassKg.map { (date: day.date, kilograms: $0) }
            }
            healthProfile = DemoPhysiology.profile
            mergeLocalLogs()
            todayCheckIn = fetchTodayCheckIn(from: context)
            acwr = computeACWR(from: context)
            let usable = healthSeries.filter(\.hasReadinessData)
            if let assembled = DayAssembler.assemble(series: usable, acwr: acwr) {
                day = assembled
                recommendation = RecommendationEngine.recommend(
                    RecommendationInput(readiness: assembled.readiness,
                                        checkIn: todayCheckIn, acwr: acwr))
            }
            hasOnboardingHealthData = true
            phase = .ready
            return
        }
        #endif

        if requestHealthAccess { UserDefaults.standard.set(false, forKey: Self.healthSkipKey) }
        if UserDefaults.standard.bool(forKey: Self.healthSkipKey) {
            healthSeries = []; healthWeight = nil; mergeLocalLogs(); day = nil; recommendation = nil; hasOnboardingHealthData = false
            healthProfile = HealthProfile()
            phase = needsOnboarding ? .needsOnboarding : .ready
            return
        }

        do {
            guard HealthKitSource.isAvailable else { throw HealthSourceError.unavailable }

            if (requestHealthAccess || seedSimulatorData), !healthAuthorizationRequested {
                #if targetEnvironment(simulator)
                try await healthKit.requestAuthorization(
                    alsoShare: seedSimulatorData ? HealthKitSeeder.shareTypes : [])
                #else
                try await healthKit.requestAuthorization()
                #endif
                healthAuthorizationRequested = true
            }
            onAuthorized?()
            #if targetEnvironment(simulator)
            if seedSimulatorData {
                let hasHistory = await healthKit.hasAnyData()
                let todayFixture = try? await healthKit.dailySeries(days: 1)
                if !hasHistory || todayFixture?.last?.hasReadinessData != true {
                    seededSampleCount = try? await HealthKitSeeder.seed(days: hasHistory ? 1 : Self.historyDays,
                                                                        into: healthKit)
                }
            }
            #endif

            healthProfile = await healthKit.healthProfile()
            let localMealIDs = ((try? context.fetch(FetchDescriptor<MealLog>())) ?? []).map(\.exportID)
            let fetched = try await healthKit.dailySeries(days: Self.historyDays, excludingMealIDs: localMealIDs)
            hasOnboardingHealthData = !DailyPhysiology.coachHealthContext(fetched).metrics.isEmpty
            // Authorization completion alone does not prove read access. Only fresh
            // records or characteristics can produce the connection celebration.
            onHealthRead?(hasOnboardingHealthData || healthProfile.sanitized() != HealthProfile())
            let usable = fetched.filter(\.hasReadinessData)
            #if DEBUG
            HealthStreamAudit.report(fetched)
            #endif

            healthReadError = nil
            healthSeries = fetched
            healthWeight = await healthKit.latestBodyMass()
            mergeLocalLogs()
            todayCheckIn = fetchTodayCheckIn(from: context)
            acwr = computeACWR(from: context)
            guard let latest = usable.last, Calendar.current.isDateInToday(latest.date),
                  let assembled = DayAssembler.assemble(series: usable, acwr: acwr), usable.count >= 2,
                  !assembled.readings.isEmpty else {
                day = nil
                recommendation = nil
                phase = needsOnboarding ? .needsOnboarding : .ready
                return
            }
            day = assembled
            persistMetrics(assembled, into: context)

            todayCheckIn = fetchTodayCheckIn(from: context)
            acwr = computeACWR(from: context)

            let planned = plannedToday(templates: templates)

            let rec = RecommendationEngine.recommend(RecommendationInput(
                readiness: assembled.readiness,
                checkIn: todayCheckIn,
                acwr: acwr,
                hasPlannedLowerBody: planned?.orderedExercises
                    .contains { $0.muscleGroup.isLowerBody } ?? false,
                hasPlannedConditioning: false))

            recommendation = rec
            persistRecommendation(rec, readiness: assembled.readiness, into: context)
            todayResponse = fetchTodayResponse(from: context)
            recentInsight = computeInsight(from: context)

            hasProgram = !templates.isEmpty
            goal = storedGoal(from: context)
            // A missing programme is no longer a wall — the home screen asks for one
            // in place, and only for the goals that need it.
            phase = needsOnboarding ? .needsOnboarding : .ready

        } catch {
            healthReadError = error.localizedDescription
            if let day, !Calendar.current.isDateInToday(day.date) { self.day = nil; recommendation = nil }
            phase = needsOnboarding ? .needsOnboarding : .ready
        }
    }

    func startBackgroundDelivery() {
        guard !UserDefaults.standard.bool(forKey: Self.healthSkipKey) else { return }
        healthKit.startBackgroundDelivery { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: - Today's plan

    // MARK: - Goal

    private func storedGoal(from context: ModelContext) -> TrainingGoal? {
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        return profile.flatMap { TrainingGoal(rawValue: $0.goal) }
    }

    /// What today's screen is made of. The barbell angle is not the front page for
    /// everybody — see `HomeComposition`.
    var goals: Set<TrainingGoal> {
        if let selected = onboarding.goals, !selected.isEmpty { return selected }
        return goal.map { [$0] } ?? onboarding.selectedGoals
    }

    private var coachGoals: String? {
        let selected = TrainingGoal.allCases.filter { goals.contains($0) }
        return selected.isEmpty ? nil : selected.map(\.rawValue).joined(separator: ", ")
    }

    var homeBlocks: [HomeBlock] {
        HomeComposition.blocks(for: goals, hasProgram: hasProgram)
    }

    /// Persists the answers when the conversation hands off to the live coach.
    func completeOnboarding(_ answers: OnboardingAnswers, in context: ModelContext) {
        let answers = answers.preservingHealthDetails(from: onboarding)
        let profile = profileRow(in: context)
        if let goal = answers.goal { profile.goal = goal.rawValue }
        profile.unitsAreMetric = answers.unitsAreMetric
        if let limitations = answers.limitationsText { profile.limitations = limitations }
        if let encoded = try? JSONEncoder().encode(answers),
           let json = String(data: encoded, encoding: .utf8) {
            profile.onboardingJSON = json
        }
        try? context.save()
        onboarding = answers
        goal = answers.goal
    }

    /// The flow is over once the user has seen their own baselines, not when the goal
    /// is stored — otherwise the reveal is cut off by the app appearing behind it.
    func finishOnboarding() {
        onboardingFinished = true
        if goal != nil { phase = .ready }
    }

    private func profileRow(in context: ModelContext) -> UserProfile {
        if let existing = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first {
            return existing
        }
        let created = UserProfile()
        context.insert(created)
        return created
    }

    func setGoals(_ selected: Set<TrainingGoal>, in context: ModelContext) {
        guard !selected.isEmpty else { return }
        let profile = profileRow(in: context)
        onboarding.setGoals(selected)
        if let marker = onboarding.goal { profile.goal = marker.rawValue }
        if let encoded = try? JSONEncoder().encode(onboarding),
           let json = String(data: encoded, encoding: .utf8) {
            profile.onboardingJSON = json
        }
        try? context.save()
        goal = onboarding.goal
        phase = .ready
    }

    func plannedToday(templates: [WorkoutTemplate]) -> WorkoutTemplate? {
        let sorted = templates.sorted { $0.order < $1.order }
        if let date = UserDefaults.standard.object(forKey: "training.today.date") as? Date,
           Calendar.current.isDateInToday(date),
           let chosen = sorted.first(where: { $0.persistentModelID == selectedTemplateID }) { return chosen }
        let completed = context.flatMap { try? $0.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date, order: .reverse)])) } ?? []
        if let last = completed.first(where: { $0.isComplete }),
           let index = sorted.firstIndex(where: { $0.name == last.templateName }), !sorted.isEmpty {
            return sorted[(index + 1) % sorted.count]
        }
        return sorted.first
    }

    // MARK: - Check-in

    func saveCheckIn(_ checkIn: CheckIn) async {
        guard let context else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let existing = (try? context.fetch(FetchDescriptor<CheckInRow>())) ?? []
        for row in existing where Calendar.current.isDate(row.date, inSameDayAs: today) {
            context.delete(row)
        }
        context.insert(CheckInRow(date: today, checkIn: checkIn))
        try? context.save()
        await refresh()
    }

    private func fetchTodayResponse(from context: ModelContext) -> RecommendationResponse? {
        let today = Calendar.current.startOfDay(for: Date())
        let rows = (try? context.fetch(FetchDescriptor<RecommendationRow>())) ?? []
        return rows.first { Calendar.current.isDate($0.date, inSameDayAs: today) }?.response
    }

    private func fetchTodayCheckIn(from context: ModelContext) -> CheckIn? {
        let today = Calendar.current.startOfDay(for: Date())
        let rows = (try? context.fetch(FetchDescriptor<CheckInRow>())) ?? []
        return rows.first { Calendar.current.isDate($0.date, inSameDayAs: today) }?.checkIn
    }

    // MARK: - Feedback loop

    func record(_ response: RecommendationResponse) {
        guard let context else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let rows = (try? context.fetch(FetchDescriptor<RecommendationRow>())) ?? []
        guard let row = rows.first(where: { Calendar.current.isDate($0.date, inSameDayAs: today) })
        else { return }
        row.responseRaw = response.rawValue
        try? context.save()
        todayResponse = response
    }



    // MARK: - Series for the dashboard

    /// Raw daily values for one metric, oldest first.
    func recentSeries(_ kind: MetricKind, days: Int = 14) -> [Double] {
        let values: [Double?] = series.map { physiology in
            switch kind {
            case .hrv: return physiology.hrvSDNN
            case .restingHeartRate: return physiology.restingHeartRate
            case .sleepDebt: return physiology.sleepHours.map { DayAssembler.sleepNeedHours - $0 }
            case .respiratoryRate: return physiology.respiratoryRate
            case .bloodOxygen: return physiology.bloodOxygenPercent
            }
        }
        return Array(values.compactMap { $0 }.suffix(days))
    }

    func sleepHoursSeries(days: Int = 14) -> [Double] {
        Array(series.compactMap(\.sleepHours).suffix(days))
    }

    var latestSleepHours: Double? { series.last.flatMap { Calendar.current.isDateInToday($0.date) ? $0.sleepHours : nil } }

    func sleepHours(on date: Date) -> Double? {
        let calendar = Calendar.current
        return series.first { calendar.isDate($0.date, inSameDayAs: date) }?.sleepHours
    }

    func baseline(_ kind: MetricKind) -> Double? {
        day?.readings.first { $0.kind == kind }?.baseline
    }

    func reading(_ kind: MetricKind) -> MetricReading? {
        day?.readings.first { $0.kind == kind }
    }

    // MARK: - Ring figures
    //
    // Each ring needs a number, and each of these is a real quantity rather than a
    // score someone made up.

    /// Today's recovery, with everything that moved it.
    ///
    /// The ring used to run the composite through a standard normal CDF as though it
    /// were a single z-score, which compressed it into roughly 20...80 and made the
    /// worst mornings unreachable. `RecoveryScore` owns the transfer now, and the
    /// readiness state and the session advice are read off the same scale.
    var recoveryScore: SignalScore {
        // Dated, like the other two. Left open past midnight the app used to show
        // yesterday's recovery beside a sleep ring that had already gone to a dash.
        guard let day, Calendar.current.isDateInToday(day.date) else {
            return SignalScore(kind: .recovery, value: nil, band: nil, contributors: [],
                               coverage: .unavailable, missing: ["Health data"],
                               modelVersion: ReadinessEngine.modelVersion)
        }
        return RecoveryScore.of(day.readiness, readings: day.readings, history: metricHistory())
    }

    /// Floored at 1: a measured zero and a missing measurement must not render alike.
    var recoveryPercent: Int? { recoveryScore.value.map { max(1, Int($0.rounded())) } }

    /// The trailing values behind each contributor, for the chart its row expands to.
    private func metricHistory(days: Int = 28, endingOn date: Date = Date()) -> [MetricKind: [Double]] {
        let cutoff = Calendar.current.startOfDay(for: date).addingTimeInterval(86_399)
        let recent = Array(series.filter { $0.date <= cutoff }.suffix(days))
        var out: [MetricKind: [Double]] = [:]
        var nights: [Double] = []
        out[.sleepDebt] = recent.compactMap { day -> Double? in
            guard let hours = day.sleepHours else { return nil }
            nights.append(hours)
            return SleepDebt.of(nights: nights).hours
        }
        for kind in MetricKind.allCases {
            let values = recent.compactMap { day -> Double? in
                switch kind {
                case .hrv: return day.hrvSDNN
                case .restingHeartRate: return day.restingHeartRate
                // The balance as it stood, matching the number the row shows. It used
                // to be last night's shortfall — a different quantity on a different
                // scale, drawn under a reference line taken from the other one.
                case .sleepDebt: return nil
                case .respiratoryRate: return day.respiratoryRate
                case .bloodOxygen: return day.bloodOxygenPercent
                }
            }
            if !values.isEmpty, out[kind] == nil { out[kind] = values }
        }
        return out
    }

    /// The three scores for any day the series covers.
    ///
    /// Every accessor below used to hard-code "today", which meant the app could only
    /// ever describe this morning. The engines never cared — each one reads a series
    /// ending at the day in question — so a calendar is a matter of passing a date.
    func scores(on date: Date, context: ModelContext? = nil)
    -> (recovery: SignalScore, sleep: SignalScore, strain: SignalScore) {
        (recoveryScore(on: date), sleepScore(on: date), strainScore(on: date, context: context))
    }

    func recoveryScore(on date: Date) -> SignalScore {
        let calendar = Calendar.current
        let upToDate = series.filter { $0.date <= calendar.startOfDay(for: date).addingTimeInterval(86_399) }
        // Dated, like everything else on this path. Passing today's ratio meant one live
        // spike capped every past day in the calendar at 66 and hung a contributor row
        // on each of them about a spike that had not happened yet.
        let ratio = context.flatMap { computeACWR(from: $0, on: date) }
        guard let assembled = DayAssembler.assemble(series: upToDate.filter(\.hasReadinessData),
                                                    acwr: ratio),
              calendar.isDate(assembled.date, inSameDayAs: date) else {
            return SignalScore(kind: .recovery, value: nil, band: nil, contributors: [],
                               coverage: .unavailable, missing: ["Health data"],
                               modelVersion: ReadinessEngine.modelVersion)
        }
        return RecoveryScore.of(assembled.readiness, readings: assembled.readings,
                                history: metricHistory(endingOn: date))
    }

    /// Last night against what it needed to be, with the structure that adjusted it.
    var sleepScore: SignalScore { sleepScore(on: Date()) }

    func sleepScore(on date: Date) -> SignalScore {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let current = series.last { calendar.isDate($0.date, inSameDayAs: today) }
        let cutoff = calendar.date(byAdding: .day, value: -28, to: today)!
        let past = series.filter { $0.date >= cutoff && $0.date < today }
        return SleepScore.of(SleepInput(
            breakdown: current?.sleep,
            durationHours: current?.sleepHours,
            history: past.compactMap(\.sleep),
            priorNights: sleepNights(upTo: date),
            // Yesterday's load is what tonight has to recover from, not today's, which
            // has not happened yet when the score is read in the morning.
            strain: strainScore(on: calendar.date(byAdding: .day, value: -1, to: today) ?? today,
                                context: nil).value,
            sleepingHeartRate: current?.sleepingHeartRate,
            daytimeHeartRate: current?.wakingHeartRate))
    }
    var sleepPercent: Int? { sleepScore.value.map { max(1, Int($0.rounded())) } }

    /// The running balance, as its own thing rather than folded into the night's score.
    var sleepDebt: SleepDebt { sleepDebt(on: Date()) }

    func sleepDebt(on date: Date) -> SleepDebt {
        SleepDebt.of(nights: sleepNights(upTo: date))
    }

    /// The one night list both the score and the debt card learn from.
    ///
    /// They used to take different slices — the score twenty-eight prior nights, the
    /// card the whole series including last night — so they learned different needs and
    /// contradicted each other on the same screen: "your need was 7.0 hours" above a
    /// card saying twelve hours behind.
    private func sleepNights(upTo date: Date, days: Int = 28) -> [Double] {
        let cutoff = Calendar.current.startOfDay(for: date).addingTimeInterval(86_399)
        return Array(series.filter { $0.date <= cutoff }.compactMap(\.sleepHours).suffix(days))
    }

    /// Kept as the labelled fallback for anybody without a heart rate trace.
    var dailyStrain: DailyStrainResult? {
        DailyStrain.evaluate(days: series.map { DailyActivity(date: $0.date,
            activeEnergyKcal: $0.activeEnergyKcal, exerciseMinutes: $0.exerciseMinutes,
            steps: $0.steps, workoutEnergyKcal: $0.workoutEnergyKcal, workoutMinutes: $0.workoutMinutes) })
    }

    func strainScore(context: ModelContext?) -> SignalScore {
        strainScore(on: Date(), context: context)
    }

    func strainScore(on date: Date, context: ModelContext?) -> SignalScore {
        let calendar = Calendar.current
        let day = series.last { calendar.isDate($0.date, inSameDayAs: date) }
        let activity = series.map {
            DailyActivity(date: $0.date, activeEnergyKcal: $0.activeEnergyKcal,
                          exerciseMinutes: $0.exerciseMinutes, steps: $0.steps,
                          workoutEnergyKcal: $0.workoutEnergyKcal,
                          workoutMinutes: $0.workoutMinutes)
        }
        return StrainScore.of(StrainInput(
            samples: Self.waking(day),
            restingHeartRate: baseline(.restingHeartRate) ?? day?.restingHeartRate,
            ageYears: healthProfile.ageYears(),
            biologicalSex: healthProfile.biologicalSex,
            observedMaxHeartRate: series.compactMap(\.heartRateMax).max(),
            hardSets: hardSets(on: date, context: context),
            // A past day is read whole; today is read part-way through.
            readAt: Calendar.current.isDateInToday(date)
                ? Date() : Calendar.current.startOfDay(for: date).addingTimeInterval(86_399),
            fallback: DailyStrain.evaluate(days: activity, on: date)))
    }

    var strainScore: SignalScore { strainScore(context: context) }
    func strainPercent(context: ModelContext) -> Int? {
        strainScore(context: context).value.map { max(1, Int($0.rounded())) }
    }

    /// A day's heart rate with the night cut out.
    ///
    /// Strain is what being awake cost. Leaving the night in did not move the number —
    /// the everyday load saturates either way — but it put "Everyday movement, 1,440 min"
    /// at the top of the breakdown on a rest day, under a sentence saying that was what
    /// did most of it.
    private static func waking(_ day: DailyPhysiology?) -> [HeartRateSample] {
        guard let day else { return [] }
        guard let start = day.sleep?.primarySleepStart,
              let end = day.sleep?.primarySleepEnd, end > start else {
            return day.heartRateSamples
        }
        return day.heartRateSamples.filter { $0.start < start || $0.start >= end }
    }

    private func hardSets(on date: Date, context: ModelContext?) -> Int {
        guard let context,
              let sessions = try? context.fetch(FetchDescriptor<WorkoutSession>()) else { return 0 }
        return sessions
            .filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .reduce(0) { $0 + $1.load.hardSetsByMuscle.values.reduce(0, +) }
    }

    func selectToday(_ template: WorkoutTemplate) {
        selectedTemplateID = template.persistentModelID
        hasProgram = true
        // Re-evaluate the lower-body adjustment for the selected template immediately.
        if let day, Calendar.current.isDateInToday(day.date) {
            recommendation = RecommendationEngine.recommend(RecommendationInput(
                readiness: day.readiness, checkIn: todayCheckIn, acwr: acwr,
                hasPlannedLowerBody: template.orderedExercises.contains { $0.muscleGroup.isLowerBody },
                hasPlannedConditioning: false))
        }
    }

    private func mergeLocalLogs() {
        guard let context else { return }
        var merged = healthSeries
        let weights = (try? context.fetch(FetchDescriptor<WeightLog>(sortBy: [SortDescriptor(\.date)]))) ?? []
        latestWeight = healthWeight
        if let local = weights.last, healthWeight == nil || local.date >= healthWeight!.date {
            latestWeight = (local.date, local.kilograms)
        }
        let meals = (try? context.fetch(FetchDescriptor<MealLog>())) ?? []
        func index(for date: Date) -> Int {
            if let index = merged.firstIndex(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) { return index }
            merged.append(DailyPhysiology(date: Calendar.current.startOfDay(for: date)))
            return merged.count - 1
        }
        for entry in meals {
            let i = index(for: entry.date)
            merged[i].dietaryEnergyKcal = (merged[i].dietaryEnergyKcal ?? 0) + entry.calories
            merged[i].proteinGrams = (merged[i].proteinGrams ?? 0) + entry.protein
            merged[i].carbohydrateGrams = (merged[i].carbohydrateGrams ?? 0) + entry.carbs
            merged[i].fatGrams = (merged[i].fatGrams ?? 0) + entry.fat
        }
        for entry in weights { merged[index(for: entry.date)].bodyMassKg = entry.kilograms }
        if let latestWeight { merged[index(for: latestWeight.date)].bodyMassKg = latestWeight.kilograms }
        series = merged.sorted { $0.date < $1.date }
    }

    func logWeight(kilograms: Double, toHealth: Bool) async throws -> String {
        guard BodyMass.isValid(kilograms: kilograms), let context else { throw LoggingError.invalid }
        let entry = WeightLog(kilograms: kilograms)
        context.insert(entry)
        do { try context.save() } catch { context.delete(entry); throw error }
        mergeLocalLogs()
        guard toHealth else { return "Weight saved in Jett." }
        let sample = HKQuantitySample(type: HKQuantityType(.bodyMass),
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms),
            start: entry.date, end: entry.date)
        do {
            try await healthKit.saveUserEntry([sample])
            entry.healthSynced = true
            try context.save()
            return "Weight saved in Jett and Apple Health."
        } catch { return "Weight saved in Jett. Apple Health couldn't save it. Check Health permissions in Settings." }
    }

    func logMeal(name: String, nutrition: MealNutrition, toHealth: Bool) async throws -> String {
        guard nutrition.isValid, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let context else { throw LoggingError.invalid }
        let entry = MealLog(name: name.trimmingCharacters(in: .whitespacesAndNewlines), nutrition: nutrition)
        context.insert(entry)
        do { try context.save() } catch { context.delete(entry); throw error }
        mergeLocalLogs()
        guard toHealth else { return "Meal saved." }
        let values: [(HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.dietaryEnergyConsumed, .kilocalorie(), nutrition.calories),
            (.dietaryProtein, .gram(), nutrition.protein),
            (.dietaryCarbohydrates, .gram(), nutrition.carbs), (.dietaryFatTotal, .gram(), nutrition.fat)]
        let samples = values.map { id, unit, value in HKQuantitySample(type: HKQuantityType(id),
            quantity: HKQuantity(unit: unit, doubleValue: value), start: entry.date, end: entry.date,
            metadata: ["JettMealID": entry.exportID, HKMetadataKeyWasUserEntered: true]) }
        do {
            try await healthKit.saveUserEntry(samples)
            entry.healthSynced = true; try context.save()
            return "Meal saved in Jett and Apple Health."
        } catch { return "Meal saved in Jett. Apple Health couldn't save it. Check Health permissions in Settings." }
    }

    private enum LoggingError: LocalizedError {
        case invalid
        var errorDescription: String? { "Check the values and try again." }
    }

    // MARK: - Coach context

    /// Assembles the only health information that ever leaves the device.
    func coachContext(context: ModelContext) -> CoachContext? {
        let calendar = Calendar.current

        let recommendations = (try? context.fetch(
            FetchDescriptor<RecommendationRow>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current

        let recentDays = recommendations.suffix(CoachContext.maximumRecentDays).map { row in
            CoachContext.DaySummary(
                day: formatter.string(from: row.date),
                state: row.stateRaw,
                composite: (row.composite * 100).rounded() / 100,
                volume: sessions
                    .filter { calendar.isDate($0.date, inSameDayAs: row.date) }
                    .reduce(0) { $0 + $1.load.volumeLoad })
        }

        let templates = (try? context.fetch(
            FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\.order)]))) ?? []
        let program = (plannedToday(templates: templates)?.orderedExercises ?? []).map {
            CoachContext.ExerciseSummary(name: $0.name, muscle: $0.muscleGroupRaw,
                                         sets: $0.targetSets, reps: $0.targetReps,
                                         weight: $0.workingWeight, rir: $0.targetRIR)
        }

        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first

        let health = DailyPhysiology.coachHealthContext(series)
        let currentCheckIn = fetchTodayCheckIn(from: context)
        let currentACWR = computeACWR(from: context)
        guard let day, calendar.isDateInToday(day.date), let recommendation else {
            var result = CoachContextBuilder.withoutReadiness(
                today: Date(), goal: coachGoals, limitations: profile?.limitations,
                checkIn: currentCheckIn, acwr: currentACWR, program: program, health: health)
            result.profile = CoachProfileSummary(health: effectiveHealthProfile, answers: onboarding, limitations: profile?.limitations)
            return result
        }
        var result = CoachContextBuilder.build(
            today: Date(), readiness: day.readiness, readings: day.readings,
            daysOfHistory: day.daysOfHistory, recommendation: recommendation,
            checkIn: currentCheckIn, acwr: currentACWR, recentDays: Array(recentDays),
            program: program, goal: coachGoals, limitations: profile?.limitations,
            describe: Copy.describe)
        result.health = health
        result.profile = CoachProfileSummary(health: effectiveHealthProfile, answers: onboarding, limitations: profile?.limitations)
        return result
    }

    // MARK: - Insight

    /// Pairs each logged session with the sleep that preceded it, then asks Core whether
    /// there is a pattern worth stating. Usually there is not, and it says nothing.
    private func computeInsight(from context: ModelContext) -> String? {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        guard !sessions.isEmpty else { return nil }
        let calendar = Calendar.current

        let sleepByDay = Dictionary(
            series.compactMap { physiology -> (Date, Double)? in
                guard let hours = physiology.sleepHours else { return nil }
                return (calendar.startOfDay(for: physiology.date), hours)
            }, uniquingKeysWith: { a, _ in a })

        let days: [InsightEngine.TrainingDay] = sessions.compactMap { session in
            guard let sleep = sleepByDay[calendar.startOfDay(for: session.date)] else { return nil }
            let load = session.load
            let lower = load.hardSetsByMuscle.keys.contains { $0.isLowerBody }
            return InsightEngine.TrainingDay(sleepHours: sleep,
                                             volumeLoad: load.volumeLoad,
                                             isLowerBody: lower)
        }
        return InsightEngine.sleepPerformancePattern(days)
    }

    // MARK: - Derived load

    private func computeACWR(from context: ModelContext, on date: Date = Date()) -> Double? {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        guard !sessions.isEmpty else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        var daily: [Double] = []
        for offset in stride(from: StrainEngine.chronicDays - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let volume = sessions
                .filter { calendar.isDate($0.date, inSameDayAs: date) }
                .reduce(0.0) { $0 + $1.load.volumeLoad }
            daily.append(volume)
        }
        return StrainEngine.acwr(daily: daily)
    }

    /// Volume load per day for the last `days` days, oldest first. Drives the Load card.
    func recentVolume(days: Int, context: ModelContext) -> [Double] {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return stride(from: days - 1, through: 0, by: -1).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return sessions.filter { calendar.isDate($0.date, inSameDayAs: date) }
                .reduce(0.0) { $0 + $1.load.volumeLoad }
        }
    }

    // MARK: - Persistence

    private func persistMetrics(_ assembled: AssembledDay, into context: ModelContext) {
        let calendar = Calendar.current
        let date = calendar.startOfDay(for: assembled.date)
        let existing = (try? context.fetch(FetchDescriptor<DailyMetricRow>())) ?? []
        for row in existing where calendar.isDate(row.date, inSameDayAs: date) {
            context.delete(row)
        }
        let lowConfidence = assembled.readiness.confidence == .low
        for reading in assembled.readings {
            context.insert(DailyMetricRow(date: date, kind: reading.kind, value: reading.value,
                                          baseline: reading.baseline, zScore: reading.zScore,
                                          sampleCount: reading.sampleCount,
                                          lowConfidence: lowConfidence))
        }
        try? context.save()
    }

    private func persistRecommendation(_ rec: Recommendation, readiness: ReadinessResult,
                                       into context: ModelContext) {
        let calendar = Calendar.current
        let date = calendar.startOfDay(for: Date())
        let rows = (try? context.fetch(FetchDescriptor<RecommendationRow>())) ?? []

        if let existing = rows.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            existing.update(readiness: readiness, recommendation: rec)
        } else {
            context.insert(RecommendationRow(date: date, readiness: readiness, recommendation: rec))
        }
        try? context.save()
    }
}
