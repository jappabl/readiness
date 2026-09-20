import Foundation

/// Strength work is real physiological load, and duration or average heart rate does not
/// capture it. These are the features the recommendation layer actually consumes.
public struct SessionLoad: Equatable, Sendable {
    public let volumeLoad: Double
    public let hardSetsByMuscle: [MuscleGroup: Int]
    public let sessionRPE: Double
    public let closeToFailureShare: Double
}

public enum StrainEngine {
    /// A set within 3 reps of failure is the one that drives adaptation and fatigue.
    public static let hardSetRIRThreshold = 3

    public static func sessionLoad(sets: [LiftSet], sessionRPE: Double) -> SessionLoad {
        let working = sets.filter { !$0.isWarmup }
        let volume = working.reduce(0.0) { $0 + $1.load * Double($1.reps) }

        let hard = working.filter { $0.rir <= hardSetRIRThreshold }
        var byMuscle: [MuscleGroup: Int] = [:]
        for set in hard { byMuscle[set.muscleGroup, default: 0] += 1 }

        let share = working.isEmpty ? 0 : Double(hard.count) / Double(working.count)

        return SessionLoad(volumeLoad: volume, hardSetsByMuscle: byMuscle,
                           sessionRPE: sessionRPE, closeToFailureShare: share)
    }

    public static let acuteDays = 7
    public static let chronicDays = 28

    /// Training days needed in the chronic window before the ratio means anything.
    /// One session against 27 rest days is arithmetically a 4.0 spike and tells you
    /// nothing — and a bogus spike silently caps a good morning.
    public static let minimumTrainingDays = 3

    /// Acute (7 day) against chronic (28 day) load. Above ~1.5 is a spike.
    /// Nil when there is not enough training in the window to compare against.
    /// Training days needed OUTSIDE the acute window before the ratio means anything.
    ///
    /// Counting training days alone was not enough. Three sessions crammed into the most
    /// recent week against twenty-one empty ones is arithmetically the same 4.0 spike the
    /// guard exists to reject — so a new logger's first fortnight, and anybody's first
    /// week back after a lay-off, capped every good morning at 66 and explained it with a
    /// spike that was really just the start of a record.
    public static let minimumChronicDays = 2

    /// `observedDays` is how long the app has actually been watching. The chronic mean
    /// used to divide by a fixed twenty-eight regardless, so the window was padded with
    /// days that predate the record — and a perfectly steady three-sessions-a-week
    /// logger was told they had spiked on seven consecutive days, somewhere around their
    /// second week. Raising the training-day count is the wrong lever: at six a
    /// once-a-week trainer would be gated out permanently.
    public static func acwr(daily: [Double], observedDays: Int? = nil) -> Double? {
        guard daily.count >= chronicDays else { return nil }
        let chronic = daily.suffix(chronicDays)
        guard chronic.filter({ $0 > 0 }).count >= minimumTrainingDays else { return nil }
        // The chronic window has to describe a habit, not just contain the acute one.
        let older = chronic.prefix(chronicDays - acuteDays)
        guard older.filter({ $0 > 0 }).count >= minimumChronicDays else { return nil }

        let covered = Swift.max(1, Swift.min(chronicDays, observedDays ?? chronic.count))
        let chronicMean = chronic.reduce(0, +) / Double(covered)
        guard chronicMean > 0 else { return nil }
        let acute = daily.suffix(acuteDays)
        let acuteMean = acute.reduce(0, +) / Double(acute.count)
        return acuteMean / chronicMean
    }

    /// Scales novelty so that 2.5x the recent norm reads as a full jump.
    static let noveltyFullScaleRatio = 1.5

    /// How unlike the recent norm today's session was. 0 is routine, 1 is a big jump.
    /// An easier day is not novel load — backing off is not a stressor.
    public static func novelty(todayVolume: Double, recentVolumes: [Double]) -> Double {
        guard !recentVolumes.isEmpty else { return 0 }
        let baseline = recentVolumes.reduce(0, +) / Double(recentVolumes.count)
        guard baseline > 0 else { return 0 }
        let ratio = todayVolume / baseline
        guard ratio > 1 else { return 0 }
        return min(1.0, (ratio - 1) / noveltyFullScaleRatio)
    }
}
