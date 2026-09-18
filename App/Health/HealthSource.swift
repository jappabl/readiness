import Foundation

/// One day's physiology, already reduced to daily aggregates.
/// Raw timeseries never travel past this boundary (spec 3.2).
///
/// Every field here is read from HealthKit, which means it works the same whether the
/// numbers came from an Apple Watch, an Oura ring or a Garmin — the app scores each
/// stream against the user's own history, so it never needs a vendor's own score.
struct DailyPhysiology: Sendable, Equatable {
    var date: Date

    // What the readiness model scores.
    var hrvSDNN: Double?
    var restingHeartRate: Double?
    var sleepHours: Double?
    var respiratoryRate: Double?
    var bloodOxygenPercent: Double?
    var wristTemperatureC: Double?

    // The night in detail: stages, time awake, time merely in bed.
    var sleep: SleepBreakdown?

    // Cardiac, beyond the resting number.
    var heartRateAverage: Double?
    var heartRateMin: Double?
    var heartRateMax: Double?
    var walkingHeartRateAverage: Double?
    var heartRateRecovery: Double?
    var vo2Max: Double?

    // Movement.
    var steps: Double?
    var activeEnergyKcal: Double?
    var basalEnergyKcal: Double?
    var exerciseMinutes: Double?
    var standMinutes: Double?
    var distanceKm: Double?
    var flightsClimbed: Double?
    var timeInDaylightMinutes: Double?

    // Body composition.
    var bodyMassKg: Double?
    var bodyFatPercent: Double?
    var leanBodyMassKg: Double?

    // Intake.
    var dietaryEnergyKcal: Double?
    var proteinGrams: Double?
    var carbohydrateGrams: Double?
    var fatGrams: Double?
    var waterLiters: Double?

    // Training as the watch saw it, which is not the same as what the user logged here.
    var workoutCount: Int?
    var workoutMinutes: Double?
    var workoutEnergyKcal: Double?

    var mindfulMinutes: Double?
}

extension DailyPhysiology {
    /// The scored metrics, by kind, so a chart can be drawn for whichever one the coach
    /// points at without a switch at every call site.
    func value(for kind: MetricKind) -> Double? {
        switch kind {
        case .hrv:              return hrvSDNN
        case .restingHeartRate: return restingHeartRate
        case .respiratoryRate:  return respiratoryRate
        case .bloodOxygen:      return bloodOxygenPercent
        case .sleepDebt:        return sleepHours.map { DayAssembler.sleepNeedHours - $0 }
        }
    }
}

enum HealthSourceError: LocalizedError {
    case unavailable
    case denied

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Health data isn't available on this device."
        case .denied: return "Health access was declined."
        }
    }
}

/// Everything upstream reads this, never HealthKit directly. That is what lets a
/// synthetic simulator source and a real Apple Watch history be interchangeable.
protocol HealthSource: Sendable {
    func requestAuthorization() async throws
    /// Daily aggregates, oldest first, covering the last `days` days.
    func dailySeries(days: Int) async throws -> [DailyPhysiology]
}
