import Foundation
import HealthKit

/// Reads the real HealthKit store. Read-only by design: nothing the user's watch
/// recorded is ever modified, and nothing leaves the device (constraint C3).
final class HealthKitSource: HealthSource, @unchecked Sendable {

    private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static let quantityIdentifiers: [HKQuantityTypeIdentifier] = [
        .heartRateVariabilitySDNN,
        .restingHeartRate,
        .respiratoryRate,
        .oxygenSaturation,
        .appleSleepingWristTemperature,
        .bodyTemperature,
        .bodyMass,
        .activeEnergyBurned,
        .basalEnergyBurned,
    ]

    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for id in quantityIdentifiers {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    func requestAuthorization() async throws {
        try await requestAuthorization(alsoShare: [])
    }

    /// Asked exactly once. HealthKit cannot present a second prompt while the first is
    /// dismissing — it hangs — so read and write are requested together or not at all.
    func requestAuthorization(alsoShare share: Set<HKSampleType>) async throws {
        guard Self.isAvailable else { throw HealthSourceError.unavailable }
        try await store.requestAuthorization(toShare: share, read: Self.readTypes)
    }

    func save(_ samples: [HKSample]) async throws {
        try await store.save(samples)
    }

    // MARK: - Daily aggregates

    func dailySeries(days: Int) async throws -> [DailyPhysiology] {
        guard Self.isAvailable else { throw HealthSourceError.unavailable }

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) else { return [] }

        async let hrv = dailyAverages(.heartRateVariabilitySDNN,
                                      unit: .secondUnit(with: .milli), from: start, to: end)
        async let rhr = dailyAverages(.restingHeartRate,
                                      unit: HKUnit.count().unitDivided(by: .minute()),
                                      from: start, to: end)
        async let resp = dailyAverages(.respiratoryRate,
                                       unit: HKUnit.count().unitDivided(by: .minute()),
                                       from: start, to: end)
        async let spo2 = dailyAverages(.oxygenSaturation, unit: .percent(), from: start, to: end)
        // Sleeping wrist temperature is an Apple Watch Series 8+ signal. Body
        // temperature covers everyone else, and is what a simulator can be seeded with.
        async let wrist = dailyAverages(.appleSleepingWristTemperature,
                                        unit: .degreeCelsius(), from: start, to: end)
        async let bodyTemp = dailyAverages(.bodyTemperature,
                                           unit: .degreeCelsius(), from: start, to: end)
        async let sleep = dailySleepHours(from: start, to: end)

        let (h, r, rp, o, w, bt, s) = try await (hrv, rhr, resp, spo2, wrist, bodyTemp, sleep)

        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let key = calendar.startOfDay(for: date)
            let oxygen = o[key].map { $0 * 100 }   // HealthKit stores 0...1
            return DailyPhysiology(date: key,
                                   hrvSDNN: h[key],
                                   restingHeartRate: r[key],
                                   sleepHours: s[key],
                                   respiratoryRate: rp[key],
                                   bloodOxygenPercent: oxygen,
                                   wristTemperatureC: w[key] ?? bt[key])
        }
    }

    private func dailyAverages(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                               from start: Date, to end: Date) async throws -> [Date: Double] {
        guard let type = HKQuantityType.quantityType(forIdentifier: id) else { return [:] }
        let calendar = Calendar.current
        guard let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: end) else { return [:] }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: dayAfterEnd,
                                                    options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1))

            query.initialResultsHandler = { _, results, error in
                if let error {
                    continuation.resume(throwing: error); return
                }
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: dayAfterEnd) { stat, _ in
                    if let value = stat.averageQuantity()?.doubleValue(for: unit) {
                        out[calendar.startOfDay(for: stat.startDate)] = value
                    }
                }
                continuation.resume(returning: out)
            }
            store.execute(query)
        }
    }

    /// A night's sleep is attributed to the day the user woke up on.
    private func dailySleepHours(from start: Date, to end: Date) async throws -> [Date: Double] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [:] }
        let calendar = Calendar.current
        guard let dayAfterEnd = calendar.date(byAdding: .day, value: 1, to: end),
              let windowStart = calendar.date(byAdding: .day, value: -1, to: start) else { return [:] }

        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: dayAfterEnd)
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: (result as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }

        let asleepValues: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]

        var out: [Date: Double] = [:]
        for sample in samples where asleepValues.contains(sample.value) {
            let wakeDay = calendar.startOfDay(for: sample.endDate)
            let hours = sample.endDate.timeIntervalSince(sample.startDate) / 3600
            out[wakeDay, default: 0] += hours
        }
        return out
    }

    // MARK: - Background delivery (AC2)

    /// The competitor's loudest complaint is that nothing updates unless the app is
    /// opened. This is the fix, and it is wired before anything else ships.
    func startBackgroundDelivery(onUpdate: @escaping @Sendable () -> Void) {
        let watched: [HKQuantityTypeIdentifier] = [.heartRateVariabilitySDNN, .restingHeartRate]
        for id in watched {
            guard let type = HKQuantityType.quantityType(forIdentifier: id) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
                onUpdate()
                completion()
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            let query = HKObserverQuery(sampleType: sleep, predicate: nil) { _, completion, _ in
                onUpdate()
                completion()
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: sleep, frequency: .hourly) { _, _ in }
        }
    }

    /// True when the store holds essentially nothing — which is the normal state of a
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
