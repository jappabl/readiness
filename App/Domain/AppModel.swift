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

    private(set) var series: [DailyPhysiology] = []

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
    }

    var needsOnboarding: Bool { goal == nil || !onboardingFinished }

    // MARK: - Load

    func refresh() async {
        guard let context else { return }
        if case .ready = phase {} else { phase = .loading }

        do {
            guard HealthKitSource.isAvailable else { throw HealthSourceError.unavailable }

            #if targetEnvironment(simulator)
            try await healthKit.requestAuthorization(alsoShare: HealthKitSeeder.shareTypes)
            if await !healthKit.hasAnyData() {
                seededSampleCount = try? await HealthKitSeeder.seed(days: Self.historyDays,
                                                                    into: healthKit)
            }
            #else
            try await healthKit.requestAuthorization()
            #endif

            let fetched = try await healthKit.dailySeries(days: Self.historyDays)
            let usable = fetched.filter { $0.hrvSDNN != nil || $0.restingHeartRate != nil }
            #if DEBUG
            HealthStreamAudit.report(fetched)
            #endif

            guard let assembled = DayAssembler.assemble(series: usable), usable.count >= 2 else {
                phase = .failed("No health history yet. Wear your watch overnight and come back.")
                return
            }
            day = assembled
            self.series = usable
            persistMetrics(assembled, into: context)

            todayCheckIn = fetchTodayCheckIn(from: context)
            acwr = computeACWR(from: context)

            let templates = (try? context.fetch(
                FetchDescriptor<WorkoutTemplate>(sortBy: [SortDescriptor(\.order)]))) ?? []
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
            phase = .failed(error.localizedDescription)
        }
    }

    func startBackgroundDelivery() {
        healthKit.startBackgroundDelivery { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: - Today's plan

    /// v1 has no calendar: the plan for today is the first template in the program.
    /// Scheduling is a later problem and does not change what the agent can say now.
    // MARK: - Goal

    private func storedGoal(from context: ModelContext) -> TrainingGoal? {
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
        return profile.flatMap { TrainingGoal(rawValue: $0.goal) }
    }

    /// What today's screen is made of. The barbell angle is not the front page for
    /// everybody — see `HomeComposition`.
    var homeBlocks: [HomeBlock] {
        HomeComposition.blocks(for: goal ?? .getStronger, hasProgram: hasProgram)
    }

    /// Stores everything onboarding gathered. Called before the Health prompt, so the
    /// answers survive even if the user declines access or quits on the permission sheet.
    func completeOnboarding(_ answers: OnboardingAnswers, in context: ModelContext) {
        let profile = profileRow(in: context)
        if let goal = answers.goal { profile.goal = goal.rawValue }
        profile.unitsAreMetric = answers.unitsAreMetric
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

    func setGoal(_ newGoal: TrainingGoal, in context: ModelContext) {
        let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
            ?? {
                let created = UserProfile()
                context.insert(created)
                return created
            }()
        profile.goal = newGoal.rawValue
        try? context.save()
        goal = newGoal
        phase = .ready
    }

    func plannedToday(templates: [WorkoutTemplate]) -> WorkoutTemplate? {
        templates.sorted { $0.order < $1.order }.first
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

    /// Re-runs the readiness model for each of the last `days` days, so the Readiness card
    /// can show a trend rather than a single number with no context.
    func compositeHistory(days: Int = 14) -> [Double] {
        guard series.count > 1 else { return [] }
        let start = max(1, series.count - days)
        return (start..<series.count).compactMap { end in
            DayAssembler.assemble(series: Array(series[0..<end + 1]))?.readiness.composite
        }
    }

    var latestSleepHours: Double? { series.last?.sleepHours }

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

    /// Where today sits among this user's own days. Floored at 1 so the worst morning
    /// still reads as a measurement rather than a missing one.
    var recoveryPercent: Int? {
        guard let composite = day?.readiness.composite else { return nil }
        return max(1, Percentile.percent(fromZ: composite))
    }

    /// How much of the nightly requirement was actually met.
    var sleepPercent: Int? {
        guard let hours = latestSleepHours else { return nil }
        return Int(min(100, (hours / DayAssembler.sleepNeedHours * 100).rounded()))
    }

    /// Sessions needed in the four-week window before "a typical week" means anything.
    static let minimumSessionsForLoad = 3

    /// This week's training volume against a typical week for this user.
    func strainPercent(context: ModelContext) -> Int? {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -StrainEngine.chronicDays,
                                         to: Date()) else { return nil }
        let sessions = ((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? [])
            .filter { $0.date >= cutoff }
        // One session against three empty weeks is not "100% of usual"; it is no baseline.
        guard sessions.count >= Self.minimumSessionsForLoad else { return nil }

        let daily = recentVolume(days: StrainEngine.chronicDays, context: context)
        let typicalWeek = daily.reduce(0, +) / Double(StrainEngine.chronicDays) * 7
        guard typicalWeek > 0 else { return nil }
        let thisWeek = daily.suffix(StrainEngine.acuteDays).reduce(0, +)
        return Int(min(100, (thisWeek / typicalWeek * 100).rounded()))
    }

    // MARK: - Coach context

    /// Assembles the only health information that ever leaves the device.
    func coachContext(context: ModelContext) -> CoachContext? {
        guard let day, let recommendation else { return nil }
        let calendar = Calendar.current

        let recommendations = (try? context.fetch(
            FetchDescriptor<RecommendationRow>(sortBy: [SortDescriptor(\.date)]))) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

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

        return CoachContextBuilder.build(
            today: Date(), readiness: day.readiness, readings: day.readings,
            daysOfHistory: day.daysOfHistory, recommendation: recommendation,
            checkIn: todayCheckIn, acwr: acwr, recentDays: Array(recentDays),
            program: program, goal: profile?.goal, limitations: profile?.limitations,
            describe: Copy.describe)
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

    private func computeACWR(from context: ModelContext) -> Double? {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        guard !sessions.isEmpty else { return nil }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
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
