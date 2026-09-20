import Foundation
import HealthKit

/// Writes synthetic history into the simulator's HealthKit store.
///
/// The point is to exercise the *real* read path. Serving synthetic data straight to the
/// UI would leave `HealthKitSource` (the riskiest code in the app) completely untested.
/// This way the simulator reads HRV out of HealthKit exactly as an iPhone would.
///
/// Debug builds only.
enum HealthKitSeeder {

    /// Only types a third-party app is actually allowed to write.
    ///
    /// Several of the streams the app *reads* are computed by Apple and are read-only:
    /// exercise and stand minutes, time in daylight, walking heart rate average, heart
    /// rate recovery, and sleeping wrist temperature. Requesting share authorisation
    /// for one of those does not return an error: it throws an uncaught Objective-C
    /// exception and takes the process with it, which is exactly how this app died
    /// once before. They stay off this list and are simply empty on a simulator.
    private static let writableQuantities: [HKQuantityTypeIdentifier] = [
        .heartRateVariabilitySDNN, .restingHeartRate, .respiratoryRate,
        .oxygenSaturation, .bodyTemperature, .heartRate,
        .stepCount, .activeEnergyBurned, .basalEnergyBurned,
        .distanceWalkingRunning, .flightsClimbed,
        .bodyMass, .bodyFatPercentage, .leanBodyMass,
        .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates,
        .dietaryFatTotal, .dietaryWater,
    ]

    static var shareTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>()
        for id in writableQuantities {
            if let t = HKQuantityType.quantityType(forIdentifier: id) { types.insert(t) }
        }
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let mindful = HKCategoryType.categoryType(forIdentifier: .mindfulSession) {
            types.insert(mindful)
        }
        types.insert(HKObjectType.workoutType())
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
        var burn: [(HKWorkout, HKQuantitySample)] = []

        for day in series {
            // Overnight readings land in the small hours, which is when a watch records them.
            guard let at = calendar.date(byAdding: .hour, value: 4, to: day.date),
                  let sleepEnd = calendar.date(byAdding: .hour, value: 7, to: day.date),
                  let wakingStart = calendar.date(byAdding: .hour, value: 8, to: day.date),
                  let wakingEnd = calendar.date(byAdding: .hour, value: 22, to: day.date)
            else { continue }

            /// A reading taken at a moment.
            func point(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double?) {
                guard let value, let type = HKQuantityType.quantityType(forIdentifier: id) else { return }
                samples.append(HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: unit, doubleValue: value),
                    start: at, end: at))
            }

            /// A total accumulated over the waking day. Cumulative types need a span,
            /// not an instant, or the daily statistics query has nothing to sum into.
            func total(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, _ value: Double?) {
                guard let value, value > 0,
                      let type = HKQuantityType.quantityType(forIdentifier: id) else { return }
                samples.append(HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: unit, doubleValue: value),
                    start: wakingStart, end: wakingEnd))
            }

            let bpm = HKUnit.count().unitDivided(by: .minute())
            point(.heartRateVariabilitySDNN, .secondUnit(with: .milli), day.hrvSDNN)
            point(.restingHeartRate, bpm, day.restingHeartRate)
            point(.respiratoryRate, bpm, day.respiratoryRate)
            point(.oxygenSaturation, .percent(), day.bloodOxygenPercent.map { $0 / 100 })
            point(.bodyTemperature, .degreeCelsius(), day.wristTemperatureC)
            point(.heartRate, bpm, day.heartRateAverage)
            point(.bodyMass, .gramUnit(with: .kilo), day.bodyMassKg)
            point(.bodyFatPercentage, .percent(), day.bodyFatPercent.map { $0 / 100 })
            point(.leanBodyMass, .gramUnit(with: .kilo), day.leanBodyMassKg)

            total(.stepCount, .count(), day.steps)
            total(.activeEnergyBurned, .kilocalorie(), day.activeEnergyKcal)
            total(.basalEnergyBurned, .kilocalorie(), day.basalEnergyKcal)
            total(.distanceWalkingRunning, .meterUnit(with: .kilo), day.distanceKm)
            total(.flightsClimbed, .count(), day.flightsClimbed)
            total(.dietaryEnergyConsumed, .kilocalorie(), day.dietaryEnergyKcal)
            total(.dietaryProtein, .gram(), day.proteinGrams)
            total(.dietaryCarbohydrates, .gram(), day.carbohydrateGrams)
            total(.dietaryFatTotal, .gram(), day.fatGrams)
            total(.dietaryWater, .liter(), day.waterLiters)

            samples.append(contentsOf: sleepSamples(for: day, endingAt: sleepEnd))

            if let minutes = day.mindfulMinutes, minutes > 0,
               let type = HKCategoryType.categoryType(forIdentifier: .mindfulSession),
               let start = calendar.date(byAdding: .minute, value: -Int(minutes), to: wakingEnd) {
                samples.append(HKCategorySample(type: type, value: 0, start: start, end: wakingEnd))
            }

            if let minutes = day.workoutMinutes, minutes > 0,
               let start = calendar.date(byAdding: .hour, value: 17, to: day.date),
               let end = calendar.date(byAdding: .minute, value: Int(minutes), to: start) {
                let workout = HKWorkout(activityType: .traditionalStrengthTraining,
                                        start: start, end: end)
                samples.append(workout)
                if let kcal = day.workoutEnergyKcal, kcal > 0,
                   let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                    burn.append((workout, HKQuantitySample(
                        type: type,
                        quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                        start: start, end: end)))
                }
            }
        }

        try await source.save(samples)
        // Associated after the fact: a workout has to exist in the store before
        // anything can be attached to it.
        for (workout, energy) in burn {
            try await source.associate([energy], with: workout)
        }
        return samples.count + burn.count
    }

    /// One night laid out as the watch would record it: the stages back to back, the
    /// time awake after them, and a single in-bed span covering the lot.
    private static func sleepSamples(for day: DailyPhysiology, endingAt sleepEnd: Date) -> [HKSample] {
        guard let night = day.sleep,
              let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }

        var samples: [HKSample] = []
        var cursor = sleepEnd.addingTimeInterval(-(night.asleepHours + night.awakeHours) * 3600)

        func stage(_ value: HKCategoryValueSleepAnalysis, _ hours: Double) {
            guard hours > 0 else { return }
            let end = cursor.addingTimeInterval(hours * 3600)
            samples.append(HKCategorySample(type: type, value: value.rawValue,
                                            start: cursor, end: end))
            cursor = end
        }

        stage(.asleepCore, night.coreHours)
        stage(.asleepDeep, night.deepHours)
        stage(.asleepREM, night.remHours)
        stage(.awake, night.awakeHours)

        if night.inBedHours > 0 {
            samples.append(HKCategorySample(
                type: type, value: HKCategoryValueSleepAnalysis.inBed.rawValue,
                start: sleepEnd.addingTimeInterval(-night.inBedHours * 3600), end: sleepEnd))
        }
        return samples
    }

}
