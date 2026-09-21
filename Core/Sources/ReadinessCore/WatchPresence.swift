import Foundation

/// Whether this person wears something to bed that can record stages and heart rate.
///
/// The problem this solves: a phone-only sleeper, the commonest first-run profile there
/// is, cannot ever have sleep stages or an overnight heart-rate dip, because nothing on
/// their person measures them. The app listed all four as "not counted today", every
/// morning, for ever, and not one of them was something waiting would fix.
///
/// Two facts are rendered identically and are not the same thing: absent today, which is
/// worth a line and can be acted on by charging a watch, and absent structurally, which
/// is worth saying once and never again.
///
/// Onboarding asks once, and the record corrects it from there. The answer is a starting
/// point and never a lock, so somebody who buys a watch six months in is recognised by
/// their data rather than asked again.
public enum WatchPresence {

    /// Into "no watch". A fortnight's holiday must not reclassify an owner and silence
    /// the nudge that their watch is not being worn.
    public static let daysToConcludeAbsent = 28

    /// Out of it. One week of stage data is enough to say a watch has appeared, and the
    /// congratulation should not lag a month behind the purchase.
    public static let daysToConcludePresent = 7

    /// The two things worth interrupting for, and only those.
    public enum Nudge: Sendable, Equatable {
        /// They said they wear one, and nothing has arrived for a week.
        case notWearingIt
        /// They said they do not, and stages started arriving anyway.
        case gotOne
    }

    /// - Parameters:
    ///   - saidYes: the onboarding answer. Nil when they were never asked.
    ///   - nightsWithStages: whether each recent night carried stage data, newest first.
    public static func hasWatch(saidYes: Bool?, nightsWithStages: [Bool]) -> Bool {
        // Data first, and fast. Somebody who just bought one is wearing one, whatever
        // they said in onboarding months ago.
        if nightsWithStages.prefix(daysToConcludePresent).contains(true) { return true }

        // Then the long silence, which takes four times as long to conclude because the
        // two errors are not equal: wrongly deciding somebody has no watch silences the
        // one message that would have told them theirs is off.
        let window = nightsWithStages.prefix(daysToConcludeAbsent)
        if window.count >= daysToConcludeAbsent, !window.contains(true) { return false }

        // Otherwise their own answer, and failing that whatever the record has ever
        // shown. Defaulting to no watch lists nothing; defaulting the other way lists
        // four things that will never arrive.
        return saidYes ?? nightsWithStages.contains(true)
    }

    /// What, if anything, to say. Nil is the usual answer.
    public static func nudge(saidYes: Bool?, nightsWithStages: [Bool]) -> Nudge? {
        guard let saidYes else { return nil }
        let recent = nightsWithStages.prefix(daysToConcludePresent)
        if saidYes {
            // A week of nights on the record, all empty. Fewer than that is not yet a
            // pattern, it is a weekend.
            guard recent.count >= daysToConcludePresent, !recent.contains(true) else { return nil }
            return .notWearingIt
        }
        // Confirm rather than assume: one night of stage data could be a borrowed watch
        // or a one-off, so it takes a week of them.
        guard recent.count >= daysToConcludePresent,
              recent.allSatisfy({ $0 }) else { return nil }
        return .gotOne
    }
}
