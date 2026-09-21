import ActivityKit
import Foundation

/// What the Lock Screen shows while somebody is lifting.
///
/// Compiled into both the app and the widget extension, because both sides have to agree
/// on the shape byte for byte. It is deliberately tiny: a Live Activity is read at arm's
/// length by somebody between sets, and everything in here has to survive being glanced
/// at in a mirror.
struct WorkoutActivityAttributes: ActivityAttributes {

    /// The part that changes as the session goes.
    struct ContentState: Codable, Hashable {
        var exercise: String
        var setsDone: Int
        var setsPlanned: Int
        /// When the current rest ends, or nil when nobody is resting.
        ///
        /// An instant rather than a remaining count: `Text(timerInterval:)` counts it
        /// down on the device, so the rest timer ticks every second without the app
        /// waking once to push it.
        var restEnds: Date?
        var totalSets: Int
    }

    var templateName: String
    var startedAt: Date
}
