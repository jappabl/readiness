import Foundation
import HealthKit

/// Reads the real HealthKit store. Read-only by design: nothing the user's watch
/// recorded is ever modified. Only derived coach summaries may be shared with consent.
///
/// Reading through HealthKit rather than each vendor's own API is what makes this
/// device-agnostic: an Apple Watch, an Oura ring and a Garmin all land in the same
/// store, and the app scores every stream against the user's own history, so it never
/// needs anyone's proprietary Readiness or Recovery number.
final class HealthKitSource: HealthSource, @unchecked Sendable {

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// One daily aggregate to fetch. `key` rather than the identifier alone because
    /// heart rate is read three times over, for its average, floor and ceiling.
    private struct Stream {
        let key: String
        let id: HKQuantityTypeIdentifier
        let unit: HKUnit
        let options: HKStatisticsOptions
    }

    private static let streams: [Stream] = [
        // Overnight physiology: what the readiness model scores.
        Stream(key: "hrv", id: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), options: .discreteAverage),
        Stream(key: "rhr", id: .restingHeartRate, unit: .beatsPerMinute, options: .discreteAverage),
        Stream(key: "respiratoryRate", id: .respiratoryRate, unit: .beatsPerMinute, options: .discreteAverage),
        Stream(key: "spo2", id: .oxygenSaturation, unit: .percent(), options: .discreteAverage),
        // Sleeping wrist temperature is an Apple Watch Series 8+ signal. Body
        // temperature is a separate measurement and never substitutes in its baseline.
        Stream(key: "wristTemp", id: .appleSleepingWristTemperature, unit: .degreeCelsius(), options: .discreteAverage),
        Stream(key: "bodyTemp", id: .bodyTemperature, unit: .degreeCelsius(), options: .discreteAverage),

        // Cardiac, beyond the resting number.
        Stream(key: "hrAvg", id: .heartRate, unit: .beatsPerMinute, options: .discreteAverage),
        Stream(key: "hrMin", id: .heartRate, unit: .beatsPerMinute, options: .discreteMin),
        Stream(key: "hrMax", id: .heartRate, unit: .beatsPerMinute, options: .discreteMax),
        Stream(key: "walkingHR", id: .walkingHeartRateAverage, unit: .beatsPerMinute, options: .discreteAverage),
        Stream(key: "hrRecovery", id: .heartRateRecoveryOneMinute, unit: .beatsPerMinute, options: .discreteAverage),
        Stream(key: "vo2Max", id: .vo2Max, unit: HKUnit(from: "ml/kg*min"), options: .discreteAverage),

        // Movement.
        Stream(key: "steps", id: .stepCount, unit: .count(), options: .cumulativeSum),
        Stream(key: "activeEnergy", id: .activeEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum),
        Stream(key: "basalEnergy", id: .basalEnergyBurned, unit: .kilocalorie(), options: .cumulativeSum),
        Stream(key: "exerciseMinutes", id: .appleExerciseTime, unit: .minute(), options: .cumulativeSum),
        Stream(key: "standMinutes", id: .appleStandTime, unit: .minute(), options: .cumulativeSum),
        Stream(key: "distance", id: .distanceWalkingRunning, unit: .meterUnit(with: .kilo), options: .cumulativeSum),
        Stream(key: "flights", id: .flightsClimbed, unit: .count(), options: .cumulativeSum),
        Stream(key: "daylight", id: .timeInDaylight, unit: .minute(), options: .cumulativeSum),

        // Body composition.
        Stream(key: "bodyMass", id: .bodyMass, unit: .gramUnit(with: .kilo), options: .discreteAverage),
        Stream(key: "bodyFat", id: .bodyFatPercentage, unit: .percent(), options: .discreteAverage),
        Stream(key: "leanMass", id: .leanBodyMass, unit: .gramUnit(with: .kilo), options: .discreteAverage),

        // Intake.
        Stream(key: "dietaryEnergy", id: .dietaryEnergyConsumed, unit: .kilocalorie(), options: .cumulativeSum),
        Stream(key: "protein", id: .dietaryProtein, unit: .gram(), options: .cumulativeSum),
        Stream(key: "carbs", id: .dietaryCarbohydrates, unit: .gram(), options: .cumulativeSum),
        Stream(key: "fat", id: .dietaryFatTotal, unit: .gram(), options: .cumulativeSum),
        Stream(key: "water", id: .dietaryWater, unit: .liter(), options: .cumulativeSum),
        Stream(key: "caffeine", id: .dietaryCaffeine, unit: .gramUnit(with: .milli), options: .cumulativeSum),
        Stream(key: "alcohol", id: .numberOfAlcoholicBeverages, unit: .count(), options: .cumulativeSum),
    ]

    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for stream in streams {
            if let type = HKQuantityType.quantityType(forIdentifier: stream.id) { types.insert(type) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        if let mindful = HKCategoryType.categoryType(forIdentifier: .mindfulSession) { types.insert(mindful) }
        types.insert(HKObjectType.workoutType())
        if let height = HKObjectType.quantityType(forIdentifier: .height) { types.insert(height) }
        for id: HKCharacteristicTypeIdentifier in [.dateOfBirth, .biologicalSex] {
            if let type = HKObjectType.characteristicType(forIdentifier: id) { types.insert(type) }
        }
        return types
    }

    func requestAuthorization() async throws {
        try await requestAuthorization(alsoShare: [])
    }

    /// Asked exactly once. HealthKit cannot present a second prompt while the first is
    /// dismissing (it hangs), so read and write are requested together or not at all.
    func requestAuthorization(alsoShare share: Set<HKSampleType>) async throws {
        guard Self.isAvailable else { throw HealthSourceError.unavailable }
        try await store.requestAuthorization(toShare: share, read: Self.readTypes)
    }

    func save(_ samples: [HKSample]) async throws {
        try await store.save(samples)
    }

    /// An explicit logging action, well after onboarding has dismissed its read sheet.
    /// No new read types or chained onboarding authorization requests are introduced.
    func saveUserEntry(_ samples: [HKQuantitySample]) async throws {
        let types = Set(samples.map { $0.quantityType as HKSampleType })
        if types.contains(where: { store.authorizationStatus(for: $0) == .notDetermined }) {
            try await store.requestAuthorization(toShare: types, read: [])
        }
        guard types.allSatisfy({ store.authorizationStatus(for: $0) == .sharingAuthorized }) else {
            throw HealthSourceError.denied
        }
        try await store.save(samples)
    }

    func latestBodyMass() async -> (date: Date, kilograms: Double)? {
        let type = HKQuantityType(.bodyMass)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type,
                predicate: HKQuery.predicateForSamples(withStart: nil, end: Date(), options: .strictEndDate),
                limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else { continuation.resume(returning: nil); return }
                continuation.resume(returning: (sample.endDate, sample.quantity.doubleValue(for: .gramUnit(with: .kilo))))
            }
            store.execute(query)
        }
    }

    /// Ties samples to a workout, which is what makes `workout.statistics(for:)`
    /// answer. Without it a seeded workout reads back with no energy at all.
    func associate(_ samples: [HKSample], with workout: HKWorkout) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.add(samples, to: workout) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    /// Characteristics and the latest height are useful even with no recent samples.
    /// Called after the same authorization as the daily streams, never another prompt.
    func healthProfile() async -> HealthProfile {
        guard Self.isAvailable else { return HealthProfile() }
        let birthday = try? store.dateOfBirthComponents()
        let sex = try? store.biologicalSex().biologicalSex
        let biologicalSex: HealthProfile.BiologicalSex? = sex == .female ? .female
            : sex == .male ? .male : sex == .other ? .other : nil
        let height = await latestHeightCM()
        return HealthProfile(heightCM: height, dateOfBirth: birthday,
                             biologicalSex: biologicalSex).sanitized()
    }

    private func latestHeightCM() async -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: .height) else { return nil }
        return await withCheckedContinuation { continuation in
            // Height often predates the 180-day history window. Do not discard it.
            let predicate = HKQuery.predicateForSamples(withStart: nil, end: Date(), options: .strictEndDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, _ in
                let value = (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: .meterUnit(with: .centi))
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    // MARK: - Daily aggregates

    func dailySeries(days: Int) async throws -> [DailyPhysiology] {
        try await dailySeries(days: days, excludingMealIDs: [])
    }

    func dailySeries(days: Int, excludingMealIDs: [String]) async throws -> [DailyPhysiology] {
        guard Self.isAvailable else { throw HealthSourceError.unavailable }

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) else { return [] }

        async let quantities = collect(Self.streams, from: start, to: end, excludingMealIDs: excludingMealIDs)
        async let sleep = dailySleep(from: start, to: end)
        async let workouts = dailyWorkouts(from: start, to: end)
        async let mindful = dailyCategoryMinutes(.mindfulSession, from: start, to: end)
        async let heartRate = intradayHeartRate(from: start, to: end)

        let (values, nights, sessions, mindfulMinutes) = try await (quantities, sleep, workouts, mindful)
        // Never fatal. A watchless phone has no intraday trace and the load model has a
        // labelled fallback for exactly that; failing the whole refresh over it would
        // take the other twenty streams down with it.
        let buckets = (try? await heartRate) ?? [:]

        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let day = calendar.startOfDay(for: date)
            func value(_ key: String) -> Double? { values[key]?[day] }

            let night = nights[day]
            let session = sessions[day]

            return DailyPhysiology(
                date: day,
                hrvSDNN: value("hrv"),
                restingHeartRate: value("rhr"),
                // The scored figure stays the plain total, so the readiness model reads
                // exactly what it always did; the breakdown rides alongside it.
                sleepHours: night?.recordedSleepHours,
                respiratoryRate: value("respiratoryRate"),
                bloodOxygenPercent: value("spo2").map { $0 * 100 },   // HealthKit stores 0...1
                wristTemperatureC: value("wristTemp"),
                bodyTemperatureC: value("bodyTemp"),
                sleep: night,
                heartRateAverage: value("hrAvg"),
                heartRateMin: value("hrMin"),
                heartRateMax: value("hrMax"),
                walkingHeartRateAverage: value("walkingHR"),
                heartRateRecovery: value("hrRecovery"),
                vo2Max: value("vo2Max"),
                steps: value("steps"),
                activeEnergyKcal: value("activeEnergy"),
                basalEnergyKcal: value("basalEnergy"),
                exerciseMinutes: value("exerciseMinutes"),
                standMinutes: value("standMinutes"),
                distanceKm: value("distance"),
                flightsClimbed: value("flights"),
                timeInDaylightMinutes: value("daylight"),
                bodyMassKg: value("bodyMass"),
                bodyFatPercent: value("bodyFat").map { $0 * 100 },
                leanBodyMassKg: value("leanMass"),
                dietaryEnergyKcal: value("dietaryEnergy"),
                proteinGrams: value("protein"),
                carbohydrateGrams: value("carbs"),
                fatGrams: value("fat"),
                waterLiters: value("water"),
                caffeineMg: value("caffeine"),
                alcoholicDrinks: value("alcohol"),
                heartRateSamples: buckets[day] ?? [],
                sleepingHeartRate: Self.average(buckets[day] ?? [], within: night),
                wakingHeartRate: Self.wakingAverage(buckets[day] ?? [], night: night),
                workoutCount: session?.count,
                workoutMinutes: session?.minutes,
                workoutEnergyKcal: session?.kcal,
                mindfulMinutes: mindfulMinutes[day])
        }
    }

    /// Runs every stream concurrently. A stream the user has no data for, or has
    /// declined, comes back empty rather than failing the whole day.
    private func collect(_ streams: [Stream], from start: Date,
                         to end: Date, excludingMealIDs: [String]) async throws -> [String: [Date: Double]] {
        await withTaskGroup(of: (String, [Date: Double]).self) { group in
            for stream in streams {
                group.addTask { [weak self] in
                    guard let self else { return (stream.key, [:]) }
                    let values = (try? await self.dailyStatistic(stream, from: start, to: end, excludingMealIDs: excludingMealIDs)) ?? [:]
                    return (stream.key, values)
                }
            }
            var out: [String: [Date: Double]] = [:]
            for await (key, values) in group { out[key] = values }
            return out
        }
    }

    private func dailyStatistic(_ stream: Stream, from start: Date,
                                to end: Date, excludingMealIDs: [String]) async throws -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: stream.id) else { return [:] }
        let calendar = Calendar.current
        guard let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: end) else { return [:] }

        let dates = HKQuery.predicateForSamples(withStart: start, end: dayAfterEnd,
                                                    options: .strictStartDate)
        // These entries are already in the local ledger. Exclude only our exports,
        // retaining other apps, earlier installs, other devices and QA records.
        let isFood = ["dietaryEnergy", "protein", "carbs", "fat"].contains(stream.key)
        let exported = HKQuery.predicateForObjects(withMetadataKey: "JettMealID", allowedValues: excludingMealIDs)
        let predicate = isFood && !excludingMealIDs.isEmpty ? NSCompoundPredicate(andPredicateWithSubpredicates: [dates,
            NSCompoundPredicate(notPredicateWithSubpredicate: exported)]) : dates
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: stream.options,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1))

            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error); return
                }
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: dayAfterEnd) { stat, _ in
                    let quantity: HKQuantity?
                    switch stream.options {
                    case .cumulativeSum:  quantity = stat.sumQuantity()
                    case .discreteMin:    quantity = stat.minimumQuantity()
                    case .discreteMax:    quantity = stat.maximumQuantity()
                    default:              quantity = stat.averageQuantity()
                    }
                    if let value = quantity?.doubleValue(for: stream.unit) {
                        out[calendar.startOfDay(for: stat.startDate)] = value
                    }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    // MARK: - Intraday heart rate

    /// How finely the day is bucketed.
    ///
    /// Was five minutes, which averaged a hard minute into four quiet ones before the
    /// load model saw it. TRIMP is convex in heart rate, so averaging first and scoring
    /// after systematically under-counts anything intermittent: measured, an hour of
    /// badminton lost 19% of its load, a gym circuit 22%, and a single hard minute
    /// inside a quiet bucket lost 58% of its own. Steady work was unaffected, which is
    /// exactly the signature of the averaging rather than of anything physiological.
    static let heartRateBucketMinutes = 1.0

    /// How long one reading is allowed to stand for when the next is missing.
    ///
    /// A watch samples every few minutes at rest and continuously during a workout, so
    /// at one-minute buckets most resting minutes have no reading of their own. Each
    /// bucket therefore covers the gap to the next one, which is what the heart was
    /// actually doing, rather than a fixed minute, or a quiet day would lose four
    /// fifths of itself. Capped, so a watch left on a charger stays a gap.
    static let heartRateCarryMinutes = 10.0

    /// The day's heart rate, bucketed.
    ///
    /// An average and a maximum cannot measure load: the same daily average covers an
    /// easy two hours and a savage twenty minutes, and those are not the same day. This
    /// is the one query the strain model genuinely needs, and the sleeping and waking
    /// averages fall out of it for free.
    private func intradayHeartRate(from start: Date, to end: Date) async throws -> [Date: [HeartRateSample]] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let dayAfterEnd = Calendar.current.date(byAdding: .day, value: 1, to: end)
        else { return [:] }
        let calendar = Calendar.current
        let predicate = HKQuery.predicateForSamples(withStart: start, end: dayAfterEnd,
                                                    options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: start,
                intervalComponents: DateComponents(minute: Int(Self.heartRateBucketMinutes)))

            query.initialResultsHandler = { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                // A bucket with no samples is a gap in coverage, not a bucket at zero.
                // Absent, so the load model never counts a drawer as rest.
                var readings: [(start: Date, bpm: Double)] = []
                results?.enumerateStatistics(from: start, to: dayAfterEnd) { stat, _ in
                    guard let average = stat.averageQuantity()?
                        .doubleValue(for: .beatsPerMinute), average > 0 else { return }
                    readings.append((stat.startDate, average))
                }

                // Each reading stands until the next one, capped. See
                // `heartRateCarryMinutes`.
                var out: [Date: [HeartRateSample]] = [:]
                for (index, reading) in readings.enumerated() {
                    let nextStart = index + 1 < readings.count ? readings[index + 1].start : nil
                    let gap = nextStart.map { $0.timeIntervalSince(reading.start) / 60 }
                        ?? Self.heartRateBucketMinutes
                    let minutes = min(max(gap, Self.heartRateBucketMinutes),
                                      Self.heartRateCarryMinutes)
                    out[calendar.startOfDay(for: reading.start), default: []].append(
                        HeartRateSample(start: reading.start, minutes: minutes,
                                        beatsPerMinute: reading.bpm))
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// The mean rate inside the night's own sleep window.
    private static func average(_ samples: [HeartRateSample],
                                within night: SleepBreakdown?) -> Double? {
        guard let start = night?.primarySleepStart, let end = night?.primarySleepEnd,
              end > start else { return nil }
        let inside = samples.filter { $0.start >= start && $0.start < end }
        let minutes = inside.reduce(0) { $0 + $1.minutes }
        guard minutes > 0 else { return nil }
        // Weighted by how long each reading stood for, now that they cover unequal spans.
        return inside.reduce(0) { $0 + $1.beatsPerMinute * $1.minutes } / minutes
    }

    /// The waking average, with the night cut out and the busiest quarter of the day
    /// trimmed off the top.
    ///
    /// The dip is meant to compare sleep against ordinary waking life, so a training
    /// session in the mean would flatter every athlete's night. Trimming the top quarter
    /// is cruder than classifying activity and does not need another query.
    private static func wakingAverage(_ samples: [HeartRateSample],
                                      night: SleepBreakdown?) -> Double? {
        var waking = samples
        if let start = night?.primarySleepStart, let end = night?.primarySleepEnd, end > start {
            waking = waking.filter { $0.start < start || $0.start >= end }
        }
        guard waking.count >= 4 else { return nil }
        let sorted = waking.map(\.beatsPerMinute).sorted()
        let quiet = sorted.prefix(max(1, sorted.count * 3 / 4))
        return quiet.reduce(0, +) / Double(quiet.count)
    }

    // MARK: - Sleep

    /// A night's sleep is attributed to the day the user woke up on, and overlapping
    /// samples are merged rather than summed. See `SleepAggregator`.
    private func dailySleep(from start: Date, to end: Date) async throws -> [Date: SleepBreakdown] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        let calendar = Calendar.current
        guard let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: end),
              let windowStart = calendar.date(byAdding: .day, value: -1, to: start) else { return [:] }

        let samples = try await categorySamples(type, from: windowStart, to: dayAfterEnd)
        let intervals = samples.compactMap { sample -> SleepInterval? in
            guard let stage = Self.stage(for: sample.value) else { return nil }
            return SleepInterval(start: sample.startDate, end: sample.endDate, stage: stage)
        }
        return SleepAggregator.byWakeDay(intervals, calendar: calendar)
    }

    private static func stage(for value: Int) -> SleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed:              return .inBed
        case .awake:              return .awake
        case .asleepUnspecified:  return .unspecified
        case .asleepCore:         return .core
        case .asleepDeep:         return .deep
        case .asleepREM:          return .rem
        default:                  return nil
        }
    }

    // MARK: - Workouts and sessions

    private func dailyWorkouts(from start: Date,
                               to end: Date) async throws -> [Date: (count: Int, minutes: Double, kcal: Double?)] {
        let calendar = Calendar.current
        guard let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: end) else { return [:] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: dayAfterEnd)
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (result as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        let energies = await withTaskGroup(of: (UUID, Double?).self) { group in
            for workout in workouts {
                group.addTask { [weak self] in
                    (workout.uuid, await self?.energyBurned(in: workout))
                }
            }
            var out: [UUID: Double] = [:]
            for await (id, kcal) in group { out[id] = kcal }
            return out
        }

        var out: [Date: (count: Int, minutes: Double, kcal: Double?)] = [:]
        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            var entry = out[day] ?? (count: 0, minutes: 0, kcal: Optional(0.0))
            entry.count += 1
            entry.minutes += workout.duration / 60
            entry.kcal = entry.kcal.flatMap { total in energies[workout.uuid].map { total + $0 } }
            out[day] = entry
        }
        return out
    }

    /// A workout the watch built carries its own statistics. One written by another app
    /// often does not. But the energy samples tied to it are still there, and asking
    /// the workout what belongs to it is the only way to find them.
    private func energyBurned(in workout: HKWorkout) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        else { return nil }

        if let value = workout.statistics(for: type)?
            .sumQuantity()?.doubleValue(for: .kilocalorie()), value >= 0 {
            return value
        }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: HKQuery.predicateForObjects(from: workout),
                options: .cumulativeSum) { _, statistics, _ in
                    continuation.resume(
                        returning: statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()))
                }
            store.execute(query)
        }
    }

    private func dailyCategoryMinutes(_ id: HKCategoryTypeIdentifier, from start: Date,
                                      to end: Date) async throws -> [Date: Double] {
        guard let type = HKCategoryType.categoryType(forIdentifier: id) else { return [:] }
        let calendar = Calendar.current
        guard let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: end) else { return [:] }

        let samples = try await categorySamples(type, from: start, to: dayAfterEnd)
        var out: [Date: Double] = [:]
        for sample in samples {
            let day = calendar.startOfDay(for: sample.startDate)
            out[day, default: 0] += sample.endDate.timeIntervalSince(sample.startDate) / 60
        }
        return out
    }

    private func categorySamples(_ type: HKCategoryType, from start: Date,
                                 to end: Date) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (result as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
    }

    /// Whether the watch recorded any workout overlapping a window. Used to decide
    /// whether a place somebody stayed at was plausibly a gym before asking them.
    func hadWorkout(between start: Date, and end: Date) async -> Bool {
        guard Self.isAvailable, end > start else { return false }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                      predicate: predicate, limit: 1,
                                      sortDescriptors: nil) { _, result, _ in
                continuation.resume(returning: !(result ?? []).isEmpty)
            }
            store.execute(query)
        }
    }

    // MARK: - Background delivery (AC2)

    /// The competitor's loudest complaint is that nothing updates unless the app is
    /// opened. This is the fix, and it is wired before anything else ships.
    func startBackgroundDelivery(onUpdate: @escaping @Sendable () -> Void) {
        let watched: [HKQuantityTypeIdentifier] = [.heartRateVariabilitySDNN, .restingHeartRate, .activeEnergyBurned, .appleExerciseTime, .stepCount, .bodyMass, .dietaryEnergyConsumed]
        for id in watched {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            observe(type, onUpdate: onUpdate)
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            observe(sleep, onUpdate: onUpdate)
        }
        observe(HKObjectType.workoutType(), onUpdate: onUpdate)
    }

    private func observe(_ type: HKSampleType, onUpdate: @escaping @Sendable () -> Void) {
        let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
            onUpdate()
            completion()
        }
        store.execute(query)
        store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
    }

    /// True when the store holds essentially nothing, which is the normal state of a
    /// fresh simulator, and the trigger for falling back to synthetic data.
    func hasAnyData() async -> Bool {
        guard let type = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN)
        else { return false }
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                      sortDescriptors: nil) { _, result, _ in
                continuation.resume(returning: !(result ?? []).isEmpty)
            }
            store.execute(query)
        }
    }
}

private extension HKUnit {
    static var beatsPerMinute: HKUnit { HKUnit.count().unitDivided(by: .minute()) }
}
