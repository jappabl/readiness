import Foundation

/// What Jett says when he comes up in the morning.
///
/// "Ahead of baseline. Train as planned." was the old version, and it says nothing to
/// anybody: baseline is a word this app invented for its own arithmetic, and a person
/// reading it first thing has to translate it before it means anything. Naming the two
/// numbers they can see on the same screen does the work the abstraction was standing in
/// for, and it is shorter.
///
/// Separate from `MorningVerdict`, which writes for a lock screen: that one carries a
/// glyph and a bare number because there is no context around it, and it returns nil on
/// an unremarkable morning because a notification has to earn its interruption. This one
/// always says something, because he has already flown up by the time it is read.
public enum MorningGreeting {

    /// How a signal reads in a sentence, from the band the ring is already drawing.
    static func word(for band: ScoreBand?) -> String? {
        switch band {
        case .green: return "good"
        case .yellow: return "normal"
        case .red: return "low"
        default: return nil
        }
    }

    /// "Sleep and recovery both look good", or nil when neither has a number yet.
    ///
    /// Sleep leads. It is the one of the two somebody has an opinion about before they
    /// open the app, so it is the one that makes the sentence land as a description of
    /// their night rather than a readout.
    public static func signals(recovery: SignalScore, sleep: SignalScore) -> String? {
        let night = word(for: sleep.band)
        let morning = word(for: recovery.band)
        switch (night, morning) {
        case let (night?, morning?) where night == morning:
            return "Sleep and recovery both look \(night)."
        case let (night?, morning?):
            return "Sleep looks \(night), recovery \(morning)."
        case let (night?, nil):
            return "Sleep looks \(night)."
        case let (nil, morning?):
            return "Recovery looks \(morning)."
        default:
            return nil
        }
    }

    /// The whole line: what the numbers say, then what to do about it.
    public static func sentence(recovery: SignalScore, sleep: SignalScore,
                                instruction: String) -> String {
        guard let signals = signals(recovery: recovery, sleep: sleep) else { return instruction }
        return signals + " " + instruction
    }
}
