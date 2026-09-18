import Foundation

/// One day's overnight physiology, already reduced to daily aggregates.
/// Raw timeseries never travel past this boundary (spec 3.2).
struct DailyPhysiology: Sendable, Equatable {
    var date: Date
    var hrvSDNN: Double?
    var restingHeartRate: Double?
    var sleepHours: Double?
    var respiratoryRate: Double?
    var bloodOxygenPercent: Double?
    var wristTemperatureC: Double?

    init(date: Date, hrvSDNN: Double? = nil, restingHeartRate: Double? = nil,
         sleepHours: Double? = nil, respiratoryRate: Double? = nil,
         bloodOxygenPercent: Double? = nil, wristTemperatureC: Double? = nil) {
        self.date = date
        self.hrvSDNN = hrvSDNN
        self.restingHeartRate = restingHeartRate
        self.sleepHours = sleepHours
        self.respiratoryRate = respiratoryRate
        self.bloodOxygenPercent = bloodOxygenPercent
        self.wristTemperatureC = wristTemperatureC
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
