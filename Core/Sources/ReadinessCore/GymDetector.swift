import Foundation

/// A stay somewhere, as the system reports it.
public struct GymVisit: Equatable, Sendable {
    public let arrival: Date
    /// Nil while the visit is still in progress.
    public let departure: Date?
    public let latitude: Double
    public let longitude: Double
    /// Whether the watch recorded a workout overlapping this stay.
    public let hadWorkout: Bool

    public init(arrival: Date, departure: Date?, latitude: Double, longitude: Double,
                hadWorkout: Bool) {
        self.arrival = arrival
        self.departure = departure
        self.latitude = latitude
        self.longitude = longitude
        self.hadWorkout = hadWorkout
    }

    public func duration(now: Date = Date()) -> TimeInterval {
        (departure ?? now).timeIntervalSince(arrival)
    }

    public var hasEnded: Bool { departure != nil }
}

/// Somewhere the user has told us they train.
public struct KnownGym: Equatable, Sendable, Codable {
    public let name: String
    public let latitude: Double
    public let longitude: Double

    public init(name: String, latitude: Double, longitude: Double) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// When to speak, and when to keep quiet.
///
/// Two different moments, and the difference between them is the whole feature. Offering
/// to take the session happens *while* you are there, because that is when it is useful.
/// Asking whether a place is your gym happens *after* you leave, because being asked to
/// name a building mid-set is the behaviour that gets an app deleted.
public enum GymDetector {

    /// Long enough to be training rather than collecting something.
    public static let offerAfter: TimeInterval = 5 * 60
    /// Long enough to have been a session, before asking what the place was.
    public static let askAfter: TimeInterval = 20 * 60
    /// Close enough to be the same building.
    public static let samePlaceMetres: Double = 150

    /// Offer to take the session: at a gym we know, still there, long enough in.
    public static func shouldOfferLogging(visit: GymVisit, knownGyms: [KnownGym],
                                          now: Date) -> Bool {
        guard !visit.hasEnded else { return false }
        guard visit.duration(now: now) >= offerAfter else { return false }
        return match(visit: visit, knownGyms: knownGyms) != nil
    }

    /// Ask what this place was: only once they have gone, only if it was long enough to
    /// be a session, and only if something physical actually happened there.
    ///
    /// That last condition is the one that matters. Visit monitoring reports every place
    /// somebody goes, so without it the app asks whether you lift at your own office.
    public static func shouldAskToConfirm(visit: GymVisit, knownGyms: [KnownGym],
                                          declined: [KnownGym]) -> Bool {
        guard visit.hasEnded else { return false }
        guard visit.hadWorkout else { return false }
        guard visit.duration() >= askAfter else { return false }
        guard match(visit: visit, knownGyms: knownGyms) == nil else { return false }
        return match(visit: visit, knownGyms: declined) == nil
    }

    public static func match(visit: GymVisit, knownGyms: [KnownGym]) -> KnownGym? {
        knownGyms.first { gym in
            metres(fromLatitude: visit.latitude, longitude: visit.longitude,
                   toLatitude: gym.latitude, longitude: gym.longitude) <= samePlaceMetres
        }
    }

    /// Haversine. Degrees of longitude narrow towards the poles, so treating a
    /// coordinate delta as a distance is wrong everywhere except the equator.
    public static func metres(fromLatitude lat1: Double, longitude lon1: Double,
                              toLatitude lat2: Double, longitude lon2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let φ1 = lat1 * .pi / 180, φ2 = lat2 * .pi / 180
        let Δφ = (lat2 - lat1) * .pi / 180
        let Δλ = (lon2 - lon1) * .pi / 180
        let a = sin(Δφ / 2) * sin(Δφ / 2)
              + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
