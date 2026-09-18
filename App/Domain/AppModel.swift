import Foundation
import HealthKit
import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppModel {

    enum Phase {
        case loading
        case needsProgram
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

    private var series: [DailyPhysiology] = []

    private let healthKit = HealthKitSource()
    private var context: ModelContext?

    static let historyDays = 180

    func attach(_ context: ModelContext) { self.context = context }

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
            recentInsight = computeInsight(from: context)

            phase = templates.isEmpty ? .needsProgram : .ready

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
    }

    var todayResponse: RecommendationResponse? {
        guard let context else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let rows = (try? context.fetch(FetchDescriptor<RecommendationRow>())) ?? []
        return rows.first { Calendar.current.isDate($0.date, inSameDayAs: today) }?.response
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
