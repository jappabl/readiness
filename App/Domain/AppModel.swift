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
    /// When the heart-rate trace was last read out of HealthKit.
    ///
    /// Today's strain is judged against how much of the day the record covers, and that
    /// question is about the data, not about the clock. `readAt: Date()` is re-evaluated on
    /// every render while `healthSeries` only changes on a refresh, and there is no health
    /// refresh on foreground, background delivery is hourly and does not observe heart rate
    /// at all, so resuming a suspended app measured this hour's clock against last hour's
    /// samples. A watch that never left the wrist was reported as a part-recorded day once
    /// the app was forty minutes stale, at any hour of the day.
    private(set) var healthReadAt: Date?
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
    /// engine's own adjustments: the coach adds to the call, it does not replace it.
    var coachAdjustment: SessionAdjustment?

    /// The day being looked at, when it is not today.
    ///
    /// The calendar used to open a sheet with three rings on it, which is a report about
    /// a day rather than the day itself. This rewinds the screen instead: the same rings,
    /// the same cards, the same coaching, as they stood that morning. Nil is today, and
    /// today is the only state in which anything can be logged, because a set you did on
    /// Tuesday does not belong to the Tuesday you are reading about on Saturday.
    var viewingDate: Date? {
        didSet {
            guard let viewingDate else { return }
            // Never forward, and never today by another name.
            if viewingDate >= Calendar.current.startOfDay(for: Date()) { self.viewingDate = nil }
        }
    }

    var viewedDay: Date { viewingDate ?? Date() }
    var isRewound: Bool { viewingDate != nil }

    /// The three rings for whichever day is on screen.
    func viewedScores(context: ModelContext?) -> (recovery: SignalScore,
                                                  sleep: SignalScore,
                                                  strain: SignalScore) {
        isRewound ? scores(on: viewedDay, context: context)
                  : (recoveryScore, sleepScore, strainScore(context: context))
    }

    /// The short list of things Jett has been told, and what it most recently wrote.
    ///
    /// Kept as one small JSON blob rather than a SwiftData model: it is capped at twenty
    /// short lines, it is always read and written whole, and nothing ever queries it.
    private(set) var coachMemory = AppModel.loadMemory() {
        didSet { Self.persist(coachMemory) }
    }

    /// Set the moment Jett writes or drops a note, so the UI can say so and then let it
    /// go. Nil again as soon as it has been shown.
    var memoryFlash: MemoryFlash?

    struct MemoryFlash: Equatable, Identifiable {
        enum Kind: Equatable { case remembered, forgot }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    /// Applies what the coach asked for and returns what to tell it back.
    ///
    /// The result string is the coach's only feedback, so it has to be honest: a note
    /// that was merged into an existing one, or a forget that matched nothing, both read
    /// differently here, or the model writes it again next message.
    @discardableResult
    func applyMemory(_ intent: CoachToolCall.Intent, now: Date = .now) -> String {
        switch intent {
        case .remember(let note):
            var memory = coachMemory
            guard let written = memory.remember(note, on: now) else {
                return "Nothing to remember."
            }
            coachMemory = memory
            memoryFlash = MemoryFlash(kind: .remembered, text: written.text)
            return "Remembered: \(written.text)"
        case .forget(let note):
            var memory = coachMemory
            guard let dropped = memory.forget(matching: note) else {
                return "Nothing on the list matched that."
            }
            coachMemory = memory
            memoryFlash = MemoryFlash(kind: .forgot, text: dropped.text)
            return "Forgotten: \(dropped.text)"
        case .adjust:
            return "Shown to the user for approval."
        }
    }

    func forgetMemory(id: UUID) {
        var memory = coachMemory
        memory.forget(id: id)
        coachMemory = memory
    }

    private static let memoryKey = "coach.memory"

    private static func persist(_ memory: CoachMemory) {
        guard let data = try? JSONEncoder().encode(memory) else { return }
        UserDefaults.standard.set(data, forKey: memoryKey)
    }

    static func loadMemory() -> CoachMemory {
        guard let data = UserDefaults.standard.data(forKey: memoryKey),
              let memory = try? JSONDecoder().decode(CoachMemory.self, from: data)
        else { return CoachMemory() }
        return memory
    }

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
            healthReadAt = Date()
            healthWeight = healthSeries.last.flatMap { day in
                day.bodyMassKg.map { (date: day.date, kilograms: $0) }
            }
            healthProfile = DemoPhysiology.profile
            mergeLocalLogs()
            todayCheckIn = fetchTodayCheckIn(from: context)
            acwr = computeACWR(from: context)
            // Dense by calendar day. Filtering the empty days out is what turned
              // "the last sixty days" into "the last sixty readings".
              let usable = healthSeries
            if let assembled = DayAssembler.assemble(series: usable, acwr: acwr,
                                                     nightScore: sleepScore.value) {
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
            healthSeries = []; healthWeight = nil; healthReadAt = nil; mergeLocalLogs(); day = nil; recommendation = nil; hasOnboardingHealthData = false
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
            // Dense by calendar day, gaps included: the baseline and trend windows are
            // calendar windows now, and compacting the empty days out is what turned "the
            // last seven days" into "the last seven readings".
            let usable = fetched
            let recorded = fetched.filter(\.hasReadinessData)
            #if DEBUG
            HealthStreamAudit.report(fetched)
            #endif

            healthReadError = nil
            healthSeries = fetched
            healthReadAt = Date()
            healthWeight = await healthKit.latestBodyMass()
            mergeLocalLogs()
            todayCheckIn = fetchTodayCheckIn(from: context)
            acwr = computeACWR(from: context)
            guard let latest = recorded.last, Calendar.current.isDateInToday(latest.date),
                  let assembled = DayAssembler.assemble(series: usable, acwr: acwr,
                                                        nightScore: sleepScore.value),
                  recorded.count >= 2,
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
            // A missing programme is no longer a wall: the home screen asks for one
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
    /// everybody. See `HomeComposition`.
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
    /// is stored. Otherwise the reveal is cut off by the app appearing behind it.
    /// Correcting one of the measures from Profile, long after onboarding.
    ///
    /// Written to the same place onboarding writes, so Health still wins where Health
    /// has a reading: this fills what it cannot see rather than overriding it.
    func updateHealthDetails(_ details: HealthProfile, in context: ModelContext) {
        var answers = onboarding
        answers.healthDetails = details.fillingMissing(
            from: onboarding.healthDetails ?? HealthProfile())
        let profile = profileRow(in: context)
        if let encoded = try? JSONEncoder().encode(answers),
           let json = String(data: encoded, encoding: .utf8) {
            profile.onboardingJSON = json
        }
        try? context.save()
        onboarding = answers
    }

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
        return RecoveryScore.of(day.readiness, readings: day.readings,
                                history: metricHistory())
    }

    /// Floored at 1: a measured zero and a missing measurement must not render alike.
    var recoveryPercent: Int? { recoveryScore.value.map { max(1, Int($0.rounded())) } }

    /// The trailing values behind each contributor, for the chart its row expands to.
    /// The trailing values behind one metric, as the app itself understands it.
    ///
    /// The coach's chart card read `DailyPhysiology.value(for:)` per day, which cannot
    /// answer for the balance (a balance is a property of a run of nights) so
    /// `[chart:sleepDebt]` drew nothing at all. Silently: the prompt tells the model a
    /// chart replaces the sentence it would have written, so it withheld the number too,
    /// for the heaviest input in the whole model.
    /// How wide a chart's window is, in calendar days.
    static let chartDays = 28

    func chartValues(_ kind: MetricKind, days: Int = chartDays) -> [Double] {
        metricHistory(days: days)[kind] ?? []
    }

    private func metricHistory(days: Int = 28, endingOn date: Date = Date()) -> [MetricKind: [Double]] {
        let cutoff = Self.endOfDay(date)
        let recent = Array(series.filter { $0.date <= cutoff }.suffix(days))
        var out: [MetricKind: [Double]] = [:]
        // `SleepDebt.history` rather than a walk over `SleepDebt.of`, which cannot produce
        // this: `of` learns its reference from every night handed to it, so a growing
        // prefix measured each point against a different one and the line ended at the
        // whole record's median while the row above it used the last 28 nights'.
        //
        // And built from `recent`, which is date-filtered. The previous version iterated
        // `series` directly, so opening a day in the calendar drew a line out of nights
        // from that day's future: a day 45 of a record whose nights 40-49 were the bad
        // ones showed a flat zero under a row correctly reading 7 hours behind.
        out[.sleepDebt] = SleepDebt.history(nights: nightlySleep(upTo: date), points: days)
        for kind in MetricKind.allCases {
            let values = recent.compactMap { day -> Double? in
                switch kind {
                case .hrv: return day.hrvSDNN
                case .restingHeartRate: return day.restingHeartRate
                // The balance as it stood, matching the number the row shows. It used
                // to be last night's shortfall: a different quantity on a different
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
    /// ever describe this morning. The engines never cared, each one reads a series
    /// ending at the day in question, so a calendar is a matter of passing a date.
    func scores(on date: Date, context: ModelContext? = nil)
    -> (recovery: SignalScore, sleep: SignalScore, strain: SignalScore) {
        (recoveryScore(on: date), sleepScore(on: date), strainScore(on: date, context: context))
    }

    /// Whether a day is worth opening: any of the three scores, or a session logged.
    ///
    /// A day can be empty of health data and still be a day somebody trained, and
    /// recovery alone was deciding for all three.
    func hasAnything(on date: Date, context: ModelContext? = nil) -> Bool {
        let day = scores(on: date, context: context)
        if day.recovery.value != nil || day.sleep.value != nil || day.strain.value != nil {
            return true
        }
        guard let context else { return false }
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        return sessions.contains {
            Calendar.current.isDate($0.date, inSameDayAs: date) && !$0.sets.isEmpty
        }
    }

    func recoveryScore(on date: Date) -> SignalScore {
        let calendar = Calendar.current
        let upToDate = series.filter { $0.date <= Self.endOfDay(date, calendar: calendar) }
        // Dated, like everything else on this path. Passing today's ratio meant one live
        // spike capped every past day in the calendar at 66 and hung a contributor row
        // on each of them about a spike that had not happened yet.
        let ratio = context.flatMap { computeACWR(from: $0, on: date) }
        guard let assembled = DayAssembler.assemble(series: upToDate, acwr: ratio,
                                                    nightScore: sleepScore(on: date).value),
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
            // The nights *behind* this one, which is what the need is documented to learn
            // from and what the structural history beside it already uses. Last night sat
            // inside its own need window, so a night better than habit raised the bar it
            // was then measured against: an 8 h night for a 6.2/8.8 sleeper scored 90.9
            // where the nights behind it justify 97.0. The penalty landed precisely on the
            // improvement band, and nowhere else.
            priorNights: sleepNights(before: date),
            // Yesterday's load is what tonight has to recover from, not today's, which
            // has not happened yet when the score is read in the morning.
            //
            // With the context, so lifting counts. Passing nil here meant `hardSets` was
            // always zero for this call: the strain card read 73 "hard" off forty hard
            // sets while the sleep card was handed 32.8 and added nothing, its own
            // sentence about how hard yesterday was omitting the session entirely.
            //
            // And only when the number is on strain's own scale. A day with no cardiac
            // trace falls back to an activity *percentile*, deliberately banded nil
            // because a percentile is not a position on an absolute scale, but
            // `SleepNeed` compares it against `strainThreshold`, so a watchless user's
            // ordinary-but-busy day read 90 and bought 36 minutes of extra need, which is
            // enough to move a band. Roughly a quarter of their days sit above their own
            // 75th percentile, so it fired on days that were physiologically unremarkable.
            strain: yesterdaysLoad(before: today),
            sleepingHeartRate: current?.sleepingHeartRate,
            daytimeHeartRate: current?.wakingHeartRate))
    }
    var sleepPercent: Int? { sleepScore.value.map { max(1, Int($0.rounded())) } }

    /// Yesterday's strain, but only if it is really strain. See `sleepScore(on:)`.
    private func yesterdaysLoad(before today: Date) -> Double? {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today
        let load = strainScore(on: yesterday, context: context)
        return load.band == nil ? nil : load.value
    }

    /// The running balance, as its own thing rather than folded into the night's score.
    var sleepDebt: SleepDebt { sleepDebt(on: Date()) }

    /// What tonight asks for: their learned baseline, plus what today's load has to be
    /// repaired. The same inputs the sleep score uses, read forward instead of back.
    func tonightsNeed(on date: Date, context: ModelContext?) -> SleepNeed {
        let learned = SleepNeed.baseline(from: sleepNights(before: date))
        return SleepNeed.of(baseline: learned.hours, learnedShare: learned.confidence,
                            strain: strainScore(on: date, context: context).value)
    }

    /// Everything the notification engine needs to decide whether to speak.
    ///
    /// Assembled here because this is the only place that holds all of it. The decision
    /// itself is Core's, and this deliberately makes none of it: no thresholds, no
    /// ordering, no "is it too early", only the readings.
    func notificationInput(now: Date = .now, record: NotificationRecord,
                           context: ModelContext?) -> NotificationDecision.Input {
        let scores = self.scores(on: now, context: context)
        // Oldest first, excluding today, which is what the engine documents wanting.
        let calendar = Calendar.current
        let recentSleep = series
            .filter { !calendar.isDate($0.date, inSameDayAs: now) && $0.date < now }
            .suffix(14)
            .compactMap { sleepScore(on: $0.date).value }
        return NotificationDecision.Input(
            now: now,
            recovery: scores.recovery,
            sleep: scores.sleep,
            recentSleepScores: Array(recentSleep),
            tonightsNeed: tonightsNeed(on: now, context: context),
            sleepDebtHours: sleepDebt.hours,
            usualBedtime: UsualBedtime.tonight(
                from: series.compactMap { $0.sleep?.primarySleepStart }, now: now),
            insight: recentInsight,
            record: record)
    }


    func sleepDebt(on date: Date) -> SleepDebt {
        let nights = nightlySleep(upTo: date)
        // One night cannot have a change since the night before it. `SleepDebt.of`
        // accumulates an empty list for `previous`, so a first-day user at six hours saw
        // "1.0 h behind, up 1.0 h since yesterday" against a yesterday with nothing in it.
        // `DayAssembler.debtReading` has always guarded this; the card did not.
        guard nights.compactMap({ $0 }).count >= 2 else {
            return SleepDebt(hours: 0, change: 0, nights: 0)
        }
        return SleepDebt.of(nights: nights)
    }

    /// The one night list both the score and the debt card learn from.
    ///
    /// They used to take different slices: the score twenty-eight prior nights, the
    /// card the whole series including last night, so they learned different needs and
    /// contradicted each other on the same screen: "your need was 7.0 hours" above a
    /// card saying twelve hours behind.
    /// One entry per calendar night, nil where nothing was recorded. The balance fades per
    /// night that *passed*, so the nights that passed have to be in the list.
    /// Every calendar night up to `date`, so the decay runs per night that passed and the
    /// reference has enough *recorded* nights under it to be a steady median.
    /// `SleepDebt` caps the reference's own sample; older nights decay to nothing.
    private func nightlySleep(upTo date: Date) -> [Double?] {
        let cutoff = Self.endOfDay(date)
        return series.filter { $0.date <= cutoff }.map(\.sleepHours)
    }

    /// The nights that were actually slept, for the need.
    ///
    /// A night count rather than a calendar window, deliberately and unlike the balance:
    /// the need is a percentile of this sleeper's own distribution, so what it wants is a
    /// sample, and a sparse wearer's twenty-eight calendar days would be a smaller one.
    private func sleepNights(before date: Date, days: Int = 28) -> [Double] {
        let start = Calendar.current.startOfDay(for: date)
        return Array(series.filter { $0.date < start }.compactMap(\.sleepHours).suffix(days))
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
            samples: Self.waking(day, asleep: asleepPeriods(spanning: date)),
            restingHeartRate: restingBaseline(upTo: date) ?? day?.restingHeartRate,
            ageYears: healthProfile.ageYears(),
            biologicalSex: healthProfile.biologicalSex,
            // As it stood *before* the day being shown. Taking the whole series meant an
            // August peak retroactively widened a March day's reserve and cost it points
            // for a beat it had not produced yet; including the day itself meant the same
            // thing happening live. A two-minute all-out finish that beats your own
            // recorded peak widens the reserve the whole day is then re-scored against, so
            // the ring went *backwards* at the moment of maximum effort: measured, a
            // 196 bpm finish cost 3.13 points against the number two minutes earlier.
            //
            // Strictly-before means the day you set a new peak is scored against your old,
            // narrower reserve and reads a little hot. On a day you went to your limit
            // that is the right direction to be wrong in.
            observedMaxHeartRate: series.filter {
                $0.date < Calendar.current.startOfDay(for: date)
            }.compactMap(\.heartRateMax).max(),
            hardSets: hardSets(on: date, context: context),
            // A past day is read whole; today is read as far as the data goes. See
            // `healthReadAt`: the wall clock runs on while the samples do not.
            readAt: Calendar.current.isDateInToday(date)
                ? (healthReadAt ?? Date())
                // The end of that day, found rather than assumed: adding 86,399 seconds
                // assumes a 24-hour day, so on a spring-forward date it lands an hour into
                // the next one and reported the last hour as a hole, and on a fall-back
                // date it stopped an hour short of the day's end.
                : Self.endOfDay(date),
            // The night's own wake time, which `primarySleepEnd` is only when the longest
            // episode of the day was a night. With none recorded, a nap became the "wake
            // time" and started the window in the afternoon, so a morning the watch spent
            // on the charger stopped being a hole at all: 22.5 against a true 73.0, called
            // a complete day. Nil falls back to what the clock can prove.
            // Every stretch of the day spent asleep, not just the one the day began with.
            // A nap the wake time refused to trust was cut out of the trace anyway and
            // then counted as unworn time, so a watch that never came off was reported as
            // a part-recorded day whenever any sleep of 40 minutes to four hours had
            // samples on both sides of it.
            asleepPeriods: asleepPeriods(spanning: date),
            primarySleep: day?.sleep?.primarySleep,
            fallback: DailyStrain.evaluate(days: activity, on: date)))
    }

    var strainScore: SignalScore { strainScore(context: context) }
    func strainPercent(context: ModelContext) -> Int? {
        strainScore(context: context).value.map { max(1, Int($0.rounded())) }
    }

    /// A day's heart rate with the night cut out.
    ///
    /// Strain is what being awake cost. Leaving the night in did not move the number
    /// (the everyday load saturates either way), but it put "Everyday movement, 1,440 min"
    /// at the top of the breakdown on a rest day, under a sentence saying that was what
    /// did most of it.
    /// The trace with the day's sleep taken out of it.
    ///
    /// Every asleep period, so this and the wear check agree about what sleep the day
    /// held. They used to disagree: this cut out the primary episode whatever it was,
    /// while the wear check only trusted an episode it considered a night, so an
    /// untrusted episode was removed from the trace and then counted as a hole in it.
    private static func waking(_ day: DailyPhysiology?,
                               asleep: [DateInterval]) -> [HeartRateSample] {
        guard let day else { return [] }
        // The same list the wear check gets, both wake days. Cutting only this day's own
        // periods left *this evening's* sleep in the trace: it belongs to tomorrow's wake
        // day, so a continuously worn watch reported "Everyday movement, 1,130 min" for a
        // waking day of 960: 170 minutes of sleep and lying awake in bed, labelled
        // movement. Which is the exact row this function exists to prevent.
        guard !asleep.isEmpty else { return day.heartRateSamples }
        return day.heartRateSamples.filter { sample in
            !asleep.contains { $0.contains(sample.start) }
        }
    }

    /// Every stretch of sleep that falls inside a day, including the night that begins in
    /// its evening.
    ///
    /// A night belongs to the day you wake up on, so a day's own breakdown holds the night
    /// that *ended* on it and nothing from its evening. A finished day's window runs to
    /// its own midnight, so that evening's sleep was never subtracted and read as a hole:
    /// every past day was reported as part-recorded, permanently, for anybody who does not
    /// sleep in their watch.
    private func asleepPeriods(spanning date: Date) -> [DateInterval] {
        let calendar = Calendar.current
        let next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return [date, next]
            .flatMap { day in
                series.first { calendar.isDate($0.date, inSameDayAs: day) }?
                    .sleep?.asleepPeriods ?? []
            }
            .sorted { $0.start < $1.start }
    }

    /// The last instant of a day, found rather than assumed.
    ///
    /// `startOfDay + 86,399` assumes every day is twenty-four hours. On a spring-forward
    /// date it lands past the *next* day's start, and `DailyPhysiology.date` is a
    /// start-of-day, so tomorrow's row satisfied `date <= cutoff`: once a year, that day's
    /// recovery rendered unavailable on data that was present, tomorrow's resting rate
    /// entered the baseline that day was scored against, and tomorrow's night entered the
    /// window behind that day's need and balance.
    static func endOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        let next = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        return calendar.startOfDay(for: next).addingTimeInterval(-1)
    }

    /// The resting-rate baseline as it stood on a given day.
    ///
    /// `baseline(.restingHeartRate)` reads today's assembly, which is a different
    /// quantity for a historical day and nil first thing in the morning before today has
    /// synced, at which point every past day silently fell back to that day's single
    /// reading, the exact thing `StrainInput.restingHeartRate` documents must not happen.
    private func restingBaseline(upTo date: Date) -> Double? {
        let cutoff = Self.endOfDay(date)
        // Dense by calendar day, so "sixty days" is sixty days here too.
        let values = series.filter { $0.date <= cutoff }.map(\.restingHeartRate)
        return BaselineEngine.evaluate(daily: values)?.mean
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

        // This sleeper's own need, not the population figure. The block used to tell Jett
        // "Sleep target 8.0h is a default, not measured sleep need" about somebody whose
        // need had been learned for months.
        let health = DailyPhysiology.coachHealthContext(
            series,
            sleepTargetHours: sleepScore.contributor(SleepScore.durationContributorID)?
                .comparison ?? SleepNeed.baselineHours)
        let currentCheckIn = fetchTodayCheckIn(from: context)
        let currentACWR = computeACWR(from: context)
        // The three numbers the person is looking at. The block carried the model's
        // internals and none of them, so with "never invent a measurement" the correct
        // behaviour was to say the recovery score could not be seen while it sat on screen
        // beside the chat.
        let onScreen = coachScores(context: context)
        let need = sleepScore.contributor(SleepScore.durationContributorID)?.comparison
        guard let day, calendar.isDateInToday(day.date), let recommendation else {
            var result = CoachContextBuilder.withoutReadiness(
                today: Date(), goal: coachGoals, limitations: profile?.limitations,
                checkIn: currentCheckIn, acwr: currentACWR, program: program, health: health)
            result.profile = CoachProfileSummary(health: effectiveHealthProfile, answers: onboarding, limitations: profile?.limitations)
            result.scores = onScreen
            result.sleepNeedHours = need
            result.memory = coachMemory.brief(asOf: Date())
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
        result.scores = onScreen
        result.sleepNeedHours = need
        result.memory = coachMemory.brief(asOf: Date())
        return result
    }

    /// The three rings as they read right now, with a caveat only where there is one.
    private func coachScores(context: ModelContext) -> [CoachContext.ScoreSummary] {
        [(Signal.recovery, recoveryScore), (.sleep, sleepScore),
         (.strain, strainScore(context: context))].map { signal, score in
            CoachContext.ScoreSummary(
                name: signal.title.lowercased(),
                value: score.value.map { Int($0.rounded()) },
                band: score.band.map { "\($0)" },
                // Only when it is not the whole picture, so an ordinary day costs no bytes.
                caveat: score.coverage == .full ? nil
                    : score.missing.isEmpty ? "partial" : "partial: " + score.missing.joined(separator: "; "))
        }
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
        // How long the app has been watching, so the chronic mean is not diluted by
        // days that predate the record.
        let first = sessions.map { calendar.startOfDay(for: $0.date) }.min()
        let observed = first.map {
            (calendar.dateComponents([.day], from: $0, to: today).day ?? 0) + 1
        }
        return StrainEngine.acwr(daily: daily, observedDays: observed)
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
