import Foundation
import CoreLocation
import UserNotifications
import os

/// Watches for arrivals and departures, and decides when Jett says something.
///
/// Visit monitoring rather than continuous location: the system reports a coordinate
/// when somebody settles somewhere and again when they leave, at almost no battery cost,
/// and that is exactly the granularity this needs. Continuous tracking would cost far
/// more and tell us nothing extra.
///
/// Nothing here is advertised. It is meant to be noticed once, by somebody already
/// standing in a gym, and never to be explained.
@Observable
@MainActor
final class GymPresence: NSObject {

    private static let log = Logger(subsystem: "com.coachjett.app", category: "gym")

    private let manager = CLLocationManager()
    private var workoutsDuring: (@Sendable (Date, Date) async -> Bool)?

    /// Set when a visit has ended somewhere unrecognised that looked like a session.
    /// Today reads this and asks, once, after the fact.
    private(set) var placeToConfirm: GymVisit?

    private(set) var knownGyms: [KnownGym] = []
    private var declined: [KnownGym] = []

    private static let knownKey = "gym.known"
    private static let declinedKey = "gym.declined"
    /// So a single visit cannot produce two nudges.
    private var offeredForArrival: Date?

    override init() {
        wantsWatching = UserDefaults.standard.bool(forKey: Self.wantsKey)
        super.init()
        knownGyms = Self.load(Self.knownKey)
        declined = Self.load(Self.declinedKey)
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = true
    }

    /// What the user asked for, which is not the same as what iOS has granted yet.
    /// The switch follows this, so it does not flick back off while a system prompt is
    /// still on screen.
    private(set) var wantsWatching: Bool {
        didSet { UserDefaults.standard.set(wantsWatching, forKey: Self.wantsKey) }
    }
    private static let wantsKey = "gym.wants"

    var isWatching: Bool { manager.authorizationStatus == .authorizedAlways }

    /// When-in-use is enough to start: visits then arrive while the app is open, and
    /// starting is what makes iOS offer the Always upgrade later. Refusing to start
    /// until Always is granted means Always is never offered.
    private var canWatch: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }

    /// True once iOS has said no in a way only Settings can undo.
    var needsSettings: Bool {
        switch manager.authorizationStatus {
        case .denied, .restricted: return wantsWatching
        default: return false
        }
    }

    /// Picks up where it left off. Never prompts: a permission dialog nobody asked for
    /// is a permission denied forever.
    func resumeIfAuthorised(workoutsDuring: @escaping @Sendable (Date, Date) async -> Bool) {
        self.workoutsDuring = workoutsDuring
        guard wantsWatching, canWatch else { return }
        manager.startMonitoringVisits()
    }

    /// Asked for only when the user has turned it on themselves, with the reason on
    /// screen in front of them.
    func requestPermission(workoutsDuring: @escaping @Sendable (Date, Date) async -> Bool) {
        self.workoutsDuring = workoutsDuring
        wantsWatching = true
        asking = true
        ask()
    }

    /// True only between the user flipping the switch and iOS settling on an answer.
    /// Without it, somebody who revoked location in Settings gets prompted again every
    /// single launch.
    private var asking = false

    /// iOS never grants Always on the first ask: it offers when-in-use, and only then
    /// will it consider the upgrade. Both steps are the same call, made twice.
    private func ask() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedWhenInUse:
            // Start first, then ask for the upgrade: iOS offers Always only to an app
            // that is visibly using location.
            manager.startMonitoringVisits()
            manager.requestAlwaysAuthorization()
        case .authorizedAlways:
            asking = false
            manager.startMonitoringVisits()
        default:
            asking = false
            Self.log.notice("visits refused; status is \(self.manager.authorizationStatus.rawValue)")
        }
    }

    func stopWatching() {
        wantsWatching = false
        manager.stopMonitoringVisits()
    }

    // MARK: - What the user decides

    func confirmGym(named name: String, at visit: GymVisit) {
        let gym = KnownGym(name: name, latitude: visit.latitude, longitude: visit.longitude)
        knownGyms.append(gym)
        Self.save(knownGyms, Self.knownKey)
        placeToConfirm = nil
        Haptics.committed()
    }

    func declineGym(at visit: GymVisit) {
        declined.append(KnownGym(name: "", latitude: visit.latitude, longitude: visit.longitude))
        Self.save(declined, Self.declinedKey)
        placeToConfirm = nil
    }

    func forgetGyms() {
        knownGyms = []
        declined = []
        Self.save(knownGyms, Self.knownKey)
        Self.save(declined, Self.declinedKey)
    }

    // MARK: - Storage

    private static func load(_ key: String) -> [KnownGym] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([KnownGym].self, from: data)
        else { return [] }
        return decoded
    }

    private static func save(_ gyms: [KnownGym], _ key: String) {
        if let data = try? JSONEncoder().encode(gyms) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - The nudge

    private func offerToLog(at gym: KnownGym) async {
        let centre = UNUserNotificationCenter.current()
        guard let granted = try? await centre.requestAuthorization(options: [.alert, .sound]),
              granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "At \(gym.name)?"
        content.body = "Tell me what you're lifting and I'll log it."
        content.sound = .default

        try? await centre.add(UNNotificationRequest(identifier: "gym.offer.\(Date().timeIntervalSince1970)",
                                                    content: content, trigger: nil))
        Self.log.notice("offered logging at \(gym.name, privacy: .public)")
    }
}

extension GymPresence: CLLocationManagerDelegate {

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // A null departure date means the visit is still in progress.
        let departure = visit.departureDate == Date.distantFuture ? nil : visit.departureDate
        let arrival = visit.arrivalDate == Date.distantPast ? Date() : visit.arrivalDate
        let coordinate = visit.coordinate

        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.handle(GymVisit(arrival: arrival, departure: departure,
                                       latitude: coordinate.latitude,
                                       longitude: coordinate.longitude,
                                       hadWorkout: false))
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.asking else {
                // Not mid-flow: resume if iOS already trusts us, and otherwise stay quiet.
                if self.wantsWatching && self.canWatch { manager.startMonitoringVisits() }
                return
            }
            // Answering the first prompt lands on when-in-use; that is the moment the
            // upgrade can be asked for, and iOS only allows asking once.
            self.ask()
        }
    }

    @MainActor
    private func handle(_ visit: GymVisit) async {
        if GymDetector.shouldOfferLogging(visit: visit, knownGyms: knownGyms, now: Date()),
           let gym = GymDetector.match(visit: visit, knownGyms: knownGyms),
           offeredForArrival != visit.arrival {
            offeredForArrival = visit.arrival
            await offerToLog(at: gym)
            return
        }

        guard visit.hasEnded else { return }

        // The workout lookup happens only for a visit that has already cleared every
        // cheap test, because it is the expensive one.
        let exerted = await workoutsDuring?(visit.arrival, visit.departure ?? Date()) ?? false
        let checked = GymVisit(arrival: visit.arrival, departure: visit.departure,
                               latitude: visit.latitude, longitude: visit.longitude,
                               hadWorkout: exerted)

        if GymDetector.shouldAskToConfirm(visit: checked, knownGyms: knownGyms,
                                          declined: declined) {
            placeToConfirm = checked
            Self.log.notice("a visit worth asking about ended")
        }
    }
}
