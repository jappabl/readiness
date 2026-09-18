import Foundation
import HealthKit

/// Writes synthetic history into the simulator's HealthKit store.
///
/// The point is to exercise the *real* read path. Serving synthetic data straight to the
/// UI would leave `HealthKitSource` — the riskiest code in the app — completely untested.
/// This way the simulator reads HRV out of HealthKit exactly as an iPhone would.
///
/// Debug builds only.
enum HealthKitSeeder {

    static var shareTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        // appleSleepingWristTemperature is READ-ONLY for third-party apps: only the
        // watch writes it, and requesting share authorisation for it throws an
        // uncaught ObjC exception. Body temperature is writable and is the same signal.
        let ids: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN, .restingHeartRate, .respiratoryRate,
            .oxygenSaturation, .bodyTemperature,
        ]
        for id in ids {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        return types
    }

    /// Authorization is requested once by `AppModel`, before this runs. Asking again here
    /// would deadlock behind the dismissing permission sheet.
    @discardableResult
    static func seed(days: Int, into source: HealthKitSource,
                     seed seedValue: UInt64 = 20260917) async throws -> Int {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthSourceError.unavailable }

        var generator = SyntheticPhysiology(seed: seedValue)
        let series = generator.series(days: days)
        let calendar = Calendar.current

        var samples: [HKSample] = []

        for day in series {
            // Overnight readings land in the small hours, which is when a watch records them.
            guard let at = calendar.date(byAdding: .hour, value: 4, to: day.date),
                  let sleepEnd = calendar.date(byAdding: .hour, value: 7, to: day.date)
            else { continue }

            func quantity(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double?) {
                guard let value, let type = HKQuantityType.quantityType(forIdentifier: id) else { return }
                samples.append(HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: unit, doubleValue: value),
                    start: at, end: at))
            }

            quantity(.heartRateVariabilitySDNN, .secondUnit(with: .milli), day.hrvSDNN)
            quantity(.restingHeartRate, HKUnit.count().unitDivided(by: .minute()), day.restingHeartRate)
            quantity(.respiratoryRate, HKUnit.count().unitDivided(by: .minute()), day.respiratoryRate)
            quantity(.oxygenSaturation, .percent(), day.bloodOxygenPercent.map { $0 / 100 })
            quantity(.bodyTemperature, .degreeCelsius(), day.wristTemperatureC)

            if let hours = day.sleepHours,
               let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis),
               let sleepStart = calendar.date(byAdding: .minute, value: -Int(hours * 60), to: sleepEnd) {
                samples.append(HKCategorySample(
                    type: sleepType,
                    value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                    start: sleepStart, end: sleepEnd))
            }
        }

        try await source.save(samples)
        return samples.count
    }
}
