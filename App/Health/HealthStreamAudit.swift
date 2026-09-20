import Foundation
import os

/// Reports which streams actually came back with data, so "we read it" can be checked
/// rather than assumed. Debug builds only — this exists because a widened read list is
/// easy to write and easy to have silently return nothing.
enum HealthStreamAudit {

    private static let log = Logger(subsystem: "com.coachjett.ios", category: "health")

    static func report(_ series: [DailyPhysiology]) {
        guard let latest = series.last else {
            log.error("STREAM AUDIT: no days returned at all")
            return
        }
        let counts: [(String, Int)] = [
            ("hrv", series.count { $0.hrvSDNN != nil }),
            ("restingHR", series.count { $0.restingHeartRate != nil }),
            ("respiratoryRate", series.count { $0.respiratoryRate != nil }),
            ("bloodOxygen", series.count { $0.bloodOxygenPercent != nil }),
            ("temperature", series.count { $0.wristTemperatureC != nil }),
            ("sleepStages", series.count { $0.sleep != nil }),
            ("heartRateAvg", series.count { $0.heartRateAverage != nil }),
            ("heartRateMin", series.count { $0.heartRateMin != nil }),
            ("heartRateMax", series.count { $0.heartRateMax != nil }),
            ("walkingHR", series.count { $0.walkingHeartRateAverage != nil }),
            ("hrRecovery", series.count { $0.heartRateRecovery != nil }),
            ("vo2Max", series.count { $0.vo2Max != nil }),
            ("steps", series.count { $0.steps != nil }),
            ("activeEnergy", series.count { $0.activeEnergyKcal != nil }),
            ("basalEnergy", series.count { $0.basalEnergyKcal != nil }),
            ("exerciseMinutes", series.count { $0.exerciseMinutes != nil }),
            ("standMinutes", series.count { $0.standMinutes != nil }),
            ("distance", series.count { $0.distanceKm != nil }),
            ("flights", series.count { $0.flightsClimbed != nil }),
            ("daylight", series.count { $0.timeInDaylightMinutes != nil }),
            ("bodyMass", series.count { $0.bodyMassKg != nil }),
            ("bodyFat", series.count { $0.bodyFatPercent != nil }),
            ("leanMass", series.count { $0.leanBodyMassKg != nil }),
            ("dietaryEnergy", series.count { $0.dietaryEnergyKcal != nil }),
            ("protein", series.count { $0.proteinGrams != nil }),
            ("carbs", series.count { $0.carbohydrateGrams != nil }),
            ("fat", series.count { $0.fatGrams != nil }),
            ("water", series.count { $0.waterLiters != nil }),
            ("workouts", series.count { ($0.workoutCount ?? 0) > 0 }),
            ("workoutEnergy", series.count { ($0.workoutEnergyKcal ?? 0) > 0 }),
            ("mindful", series.count { ($0.mindfulMinutes ?? 0) > 0 }),
        ]
        let present = counts.filter { $0.1 > 0 }
        let empty = counts.filter { $0.1 == 0 }.map(\.0)

        log.notice("STREAM AUDIT over \(series.count) days — \(present.count)/\(counts.count) streams have data")
        for (name, count) in present {
            log.notice("STREAM AUDIT   \(name): \(count) days")
        }
        if !empty.isEmpty {
            log.notice("STREAM AUDIT   EMPTY: \(empty.joined(separator: ", "))")
        }
        if let night = latest.sleep {
            log.notice("""
                STREAM AUDIT   latest night — asleep \(night.asleepHours, format: .fixed(precision: 2))h \
                (core \(night.coreHours, format: .fixed(precision: 2)) \
                deep \(night.deepHours, format: .fixed(precision: 2)) \
                rem \(night.remHours, format: .fixed(precision: 2))) \
                awake \(night.awakeHours, format: .fixed(precision: 2)) \
                inBed \(night.inBedHours, format: .fixed(precision: 2))
                """)
        }
    }
}
