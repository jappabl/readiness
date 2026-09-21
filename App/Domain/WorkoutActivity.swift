import ActivityKit
import Foundation

/// Starting, moving and ending the Lock Screen activity.
///
/// Everything here is best-effort on purpose. A Live Activity can be refused for reasons
/// the app cannot see or fix: the setting is off, too many are running, the system is
/// under pressure, and none of them are reasons to stop somebody logging a set. So
/// every call either works or does nothing, and the workout never depends on it.
@MainActor
enum WorkoutActivity {

    private static var current: Activity<WorkoutActivityAttributes>?

    static var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    static func start(template: String, exercise: String, setsPlanned: Int) {
        guard isAvailable, current == nil else { return }
        let attributes = WorkoutActivityAttributes(templateName: template, startedAt: Date())
        let state = WorkoutActivityAttributes.ContentState(
            exercise: exercise, setsDone: 0, setsPlanned: setsPlanned,
            restEnds: nil, totalSets: 0)
        current = try? Activity.request(attributes: attributes,
                                        content: .init(state: state, staleDate: nil))
    }

    static func update(exercise: String, setsDone: Int, setsPlanned: Int,
                       restEnds: Date?, totalSets: Int) {
        guard let current else { return }
        let state = WorkoutActivityAttributes.ContentState(
            exercise: exercise, setsDone: setsDone, setsPlanned: setsPlanned,
            restEnds: restEnds, totalSets: totalSets)
        Task {
            // Stale after the rest would have ended, so a forgotten session stops
            // claiming a countdown that finished an hour ago.
            await current.update(.init(state: state,
                                       staleDate: restEnds?.addingTimeInterval(60)))
        }
    }

    static func end() {
        guard let activity = current else { return }
        current = nil
        // Immediately, not on the system's own schedule: a finished workout lingering on
        // the Lock Screen is the thing people complain about with these.
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
}
