import Testing
import Foundation
@testable import ReadinessCore

/// Two different moments, and the difference matters more than the detection does.
///
/// Offering to log happens *while* you are there, because that is when it is useful.
/// Asking whether a place is your gym happens *after* you leave, because being asked to
/// name a building mid-set is the behaviour that gets an app deleted.
@Suite("Noticing a gym")
struct GymDetectorTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func visit(minutes: Double, departed: Bool, workout: Bool = true,
                       lat: Double = 37.7749, lon: Double = -122.4194) -> GymVisit {
        GymVisit(arrival: start,
                 departure: departed ? start.addingTimeInterval(minutes * 60) : nil,
                 latitude: lat, longitude: lon, hadWorkout: workout)
    }

    private var known: [KnownGym] {
        [KnownGym(name: "24 Hour Fitness", latitude: 37.7749, longitude: -122.4194)]
    }

    // MARK: Offering to log

    @Test("a long stay at your gym offers to take the session")
    func offersAtKnownGym() {
        let here = visit(minutes: 12, departed: false)
        #expect(GymDetector.shouldOfferLogging(visit: here, knownGyms: known,
                                               now: start.addingTimeInterval(12 * 60)))
    }

    @Test("walking past does not")
    func noOfferForAShortStay() {
        let here = visit(minutes: 2, departed: false)
        #expect(!GymDetector.shouldOfferLogging(visit: here, knownGyms: known,
                                                now: start.addingTimeInterval(2 * 60)))
    }

    @Test("nothing is offered once you have left")
    func noOfferAfterLeaving() {
        let gone = visit(minutes: 40, departed: true)
        #expect(!GymDetector.shouldOfferLogging(visit: gone, knownGyms: known,
                                                now: start.addingTimeInterval(60 * 60)))
    }

    @Test("a long stay somewhere unknown is not offered either")
    func noOfferAtUnknownPlace() {
        let elsewhere = visit(minutes: 30, departed: false, lat: 40.0, lon: -74.0)
        #expect(!GymDetector.shouldOfferLogging(visit: elsewhere, knownGyms: known,
                                                now: start.addingTimeInterval(30 * 60)))
    }

    // MARK: Asking whether it is a gym

    @Test("the question waits until you have left")
    func neverAsksMidVisit() {
        let here = visit(minutes: 45, departed: false, lat: 40.0, lon: -74.0)
        #expect(!GymDetector.shouldAskToConfirm(visit: here, knownGyms: known, declined: []))
    }

    @Test("a long visit with a workout in it is worth asking about")
    func asksAfterAPlausibleSession() {
        let gone = visit(minutes: 50, departed: true, workout: true, lat: 40.0, lon: -74.0)
        #expect(GymDetector.shouldAskToConfirm(visit: gone, knownGyms: known, declined: []))
    }

    @Test("a long visit with no exertion is somebody's office")
    func neverAsksWithoutExertion() {
        // The whole reason this gate exists: visit monitoring reports every place you
        // go, and being asked whether you lift at work is how an app gets deleted.
        let gone = visit(minutes: 480, departed: true, workout: false, lat: 40.0, lon: -74.0)
        #expect(!GymDetector.shouldAskToConfirm(visit: gone, knownGyms: known, declined: []))
    }

    @Test("a place you already named is never asked about again")
    func neverAsksAboutAKnownGym() {
        let gone = visit(minutes: 60, departed: true)
        #expect(!GymDetector.shouldAskToConfirm(visit: gone, knownGyms: known, declined: []))
    }

    @Test("a place you said no to is never asked about again")
    func respectsADecline() {
        let spot = KnownGym(name: "", latitude: 40.0, longitude: -74.0)
        let gone = visit(minutes: 50, departed: true, lat: 40.0, lon: -74.0)
        #expect(!GymDetector.shouldAskToConfirm(visit: gone, knownGyms: known, declined: [spot]))
    }

    @Test("a brief errand is never asked about")
    func neverAsksAboutAQuickStop() {
        let gone = visit(minutes: 6, departed: true, lat: 40.0, lon: -74.0)
        #expect(!GymDetector.shouldAskToConfirm(visit: gone, knownGyms: known, declined: []))
    }

    // MARK: Matching

    @Test("the same building is the same gym, a few streets away is not")
    func matchesByDistance() {
        let sameBlock = visit(minutes: 20, departed: false, lat: 37.7750, lon: -122.4195)
        #expect(GymDetector.match(visit: sameBlock, knownGyms: known)?.name == "24 Hour Fitness")

        let acrossTown = visit(minutes: 20, departed: false, lat: 37.8000, lon: -122.4194)
        #expect(GymDetector.match(visit: acrossTown, knownGyms: known) == nil)
    }

    @Test("distance is real metres, not degrees")
    func distanceIsSane() {
        // A hundredth of a degree of latitude is about 1.1km anywhere on earth.
        let metres = GymDetector.metres(fromLatitude: 37.0, longitude: -122.0,
                                        toLatitude: 37.01, longitude: -122.0)
        #expect(metres > 1000 && metres < 1200, "got \(metres)")
    }
}
