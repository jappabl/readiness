import Foundation

public struct Lift: Sendable, Equatable, Codable {
    public let name: String
    public let workingWeight: Double
    public let increment: Double
    public let repTarget: Int
    public let rirTarget: Int

    public init(name: String, workingWeight: Double, increment: Double, repTarget: Int, rirTarget: Int) {
        self.name = name
        self.workingWeight = workingWeight
        self.increment = increment
        self.repTarget = repTarget
        self.rirTarget = rirTarget
    }
}

public struct Prescription: Sendable, Equatable, Codable {
    public let lift: Lift
    public let prescribedLoad: Double
    public let appliedPercent: Double
    public let repTarget: Int
    public let rirTarget: Int
}

public enum PrescriptionEngine {
    public static let floorPercent: Double = -0.20
    public static let ceilingPercent: Double = 0.05

    public static func basePercent(for state: ReadinessState) -> Double {
        switch state {
        case .aboveBaseline: return 0.025
        case .atBaseline: return 0
        case .belowBaseline: return -0.07
        case .wellBelowBaseline: return -0.15
        }
    }

    public static func prescribe(lift: Lift, state: ReadinessState,
                                 multiDayTrendPresent: Bool) -> Prescription {
        var percent = min(max(basePercent(for: state), floorPercent), ceilingPercent)

        // Spec 3.4: never move more than one increment off a single morning's signal.
        if !multiDayTrendPresent, lift.workingWeight > 0 {
            let oneIncrement = lift.increment / lift.workingWeight
            percent = min(max(percent, -oneIncrement), oneIncrement)
        }

        // Round the *adjustment*, not the total. A lifter at 315 with 10 lb jumps moves
        // to 305 or 325: never to 310. The loadable grid is relative to their bar.
        let rawDelta = lift.workingWeight * percent
        let magnitude = PlateMath.round(abs(rawDelta), toIncrement: lift.increment)
        let delta = rawDelta < 0 ? -magnitude : magnitude
        let load = max(0, lift.workingWeight + delta)

        let applied = lift.workingWeight > 0
            ? (load - lift.workingWeight) / lift.workingWeight
            : 0

        return Prescription(lift: lift, prescribedLoad: load, appliedPercent: applied,
                            repTarget: lift.repTarget, rirTarget: lift.rirTarget)
    }
}
