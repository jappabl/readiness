import ActivityKit
import SwiftUI
import WidgetKit

@main
struct JettWidgets: WidgetBundle {
    var body: some Widget { WorkoutLiveActivity() }
}

/// The session, on the Lock Screen and in the Dynamic Island.
///
/// The phone is face down on a bench for most of a workout, so this is the only surface
/// the app has during the part it exists for. It answers the two questions somebody
/// actually has between sets: how long is left on the rest, and what am I on.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            lockScreen(context.state, template: context.attributes.templateName)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.exercise, systemImage: "dumbbell.fill")
                        .font(.caption).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(setLine(context.state)).font(.caption).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        if let ends = context.state.restEnds {
                            restBar(ends)
                        } else {
                            Text("\(context.state.totalSets) sets logged")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        finishLink
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
            } compactTrailing: {
                if let ends = context.state.restEnds {
                    // Fixed, or the island jitters as the digits change, and wide enough
                    // for m:ss. At 44 iOS could not promise the seconds would fit and
                    // rendered "2:--" rather than a countdown, which is worse than no
                    // timer at all: it looks like the app lost track of the rest.
                    Text(timerInterval: Date()...ends, countsDown: true)
                        .monospacedDigit().frame(width: 58)
                } else {
                    Text(setLine(context.state)).monospacedDigit()
                }
            } minimal: {
                Image(systemName: "dumbbell.fill")
            }
        }
    }

    private func lockScreen(_ state: WorkoutActivityAttributes.ContentState,
                            template: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(template, systemImage: "dumbbell.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(state.totalSets) logged")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(state.exercise)
                    .font(.title3.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text(setLine(state))
                    .font(.subheadline.weight(.medium)).monospacedDigit()
            }
            HStack(spacing: 10) {
                if let ends = state.restEnds { restBar(ends) } else { Spacer() }
                finishLink
            }
        }
    }

    /// The way out.
    ///
    /// The activity had none: it could be started from the app and then only ever
    /// ended from the app, which is the one place somebody is not looking during a
    /// workout. A phone face down on a bench with a session that cannot be closed from
    /// the screen it is on is worse than no activity at all.
    ///
    /// A link rather than a button with an intent, because ending a workout is not just
    /// dismissing this: the session has to be written as complete, and the app owns
    /// that. One tap gets them to the screen that does it.
    private var finishLink: some View {
        Link(destination: URL(string: "coachjett://finish")!) {
            Text("End")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(.white.opacity(0.18), in: Capsule())
        }
    }

    /// Counted down by the system from an end date, so nothing has to wake up to keep
    /// it honest.
    private func restBar(_ ends: Date) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "timer").font(.caption)
            Text(timerInterval: Date()...ends, countsDown: true)
                .font(.headline.monospacedDigit())
            Spacer()
        }
    }

    private func setLine(_ state: WorkoutActivityAttributes.ContentState) -> String {
        state.setsDone < state.setsPlanned
            ? "Set \(state.setsDone + 1)/\(state.setsPlanned)"
            : "Set \(state.setsDone + 1)"
    }
}
