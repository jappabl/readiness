import Foundation

/// The sessions the app starts somebody on.
///
/// The old ones were five compounds in a row with no isolation, no delts and no arms,
/// which is a strength template handed to somebody who said they want to look better.
/// Hao's words were that he would never use the preset for any reason possible, and he
/// was right: nobody's chest day is squat, deadlift, bench, row, press.
///
/// These are ordinary sessions. A heavy compound, a second angle on it, then the
/// isolation that actually finishes the muscle off, five to six movements, two to four
/// sets. Written as patterns rather than names so the same session reads correctly with
/// a barbell, a pair of dumbbells or nothing at all.
public enum SplitCatalog {

    /// One line of a session: what pattern, at what reps, and which of the options for
    /// that pattern to prefer when several are available.
    struct Slot: Sendable {
        let pattern: MovementPattern
        let reps: Int
        /// Tried in order. Anything not available falls through to the pattern's own
        /// best remaining option, so a slot is never simply dropped.
        let prefer: [String]

        init(_ pattern: MovementPattern, _ reps: Int, _ prefer: String...) {
            self.pattern = pattern
            self.reps = reps
            self.prefer = prefer
        }
    }

    struct Template: Sendable {
        let name: String
        let slots: [Slot]
    }

    // MARK: - The sessions

    static let push = Template(name: "Push", slots: [
        Slot(.horizontalPress, 8, "bench", "machine-press", "db-bench", "pushup"),
        Slot(.horizontalPress, 10, "incline-machine", "db-incline", "decline-pushup"),
        Slot(.chestIsolation, 14, "cable-fly", "db-fly", "pec-deck"),
        Slot(.verticalPress, 10, "machine-shoulder", "db-shoulder", "pike-pushup"),
        Slot(.shoulderIsolation, 15, "lateral-raise", "cable-lateral"),
        Slot(.tricep, 12, "pushdown", "overhead-ext", "chair-dip"),
    ])

    static let pull = Template(name: "Pull", slots: [
        Slot(.verticalPull, 10, "pulldown", "db-pullover", "pullup"),
        Slot(.horizontalPull, 10, "chest-row", "db-chest-row", "inverted-row"),
        Slot(.horizontalPull, 12, "cable-row", "db-row", "towel-row"),
        Slot(.backIsolation, 15, "face-pull", "prone-ytw"),
        Slot(.bicep, 10, "bb-curl", "db-curl", "chin-up"),
        Slot(.bicep, 12, "incline-curl", "hammer-curl"),
    ])

    static let legs = Template(name: "Legs", slots: [
        Slot(.squat, 8, "back-squat", "leg-press", "goblet-squat", "bw-squat"),
        Slot(.hinge, 10, "bb-rdl", "db-rdl", "back-ext", "sl-rdl"),
        Slot(.lunge, 10, "bulgarian", "db-lunge", "bw-split-squat"),
        Slot(.hamstringIsolation, 12, "leg-curl", "nordic"),
        Slot(.quadIsolation, 14, "leg-ext"),
        Slot(.calf, 15, "calf-raise", "db-calf", "bw-calf"),
    ])

    static let upper = Template(name: "Upper", slots: [
        Slot(.horizontalPress, 8, "bench", "machine-press", "db-bench", "pushup"),
        Slot(.verticalPull, 10, "pulldown", "db-pullover", "pullup"),
        Slot(.verticalPress, 10, "machine-shoulder", "db-shoulder", "pike-pushup"),
        Slot(.horizontalPull, 12, "chest-row", "db-chest-row", "inverted-row"),
        Slot(.shoulderIsolation, 15, "lateral-raise", "cable-lateral", "rear-delt-fly"),
        Slot(.bicep, 12, "db-curl", "bb-curl", "chin-up"),
        Slot(.tricep, 12, "pushdown", "overhead-ext", "chair-dip"),
    ])

    static let lower = Template(name: "Lower", slots: [
        Slot(.squat, 8, "back-squat", "leg-press", "goblet-squat", "bw-squat"),
        Slot(.hinge, 10, "bb-rdl", "db-rdl", "back-ext", "sl-rdl"),
        Slot(.lunge, 12, "bulgarian", "db-lunge", "bw-split-squat"),
        Slot(.hamstringIsolation, 12, "leg-curl", "nordic"),
        Slot(.calf, 15, "calf-raise", "db-calf", "bw-calf"),
    ])

    /// Two full body days that are not the same day twice. A and B lead on different
    /// patterns so running them back to back is a rotation rather than a repeat.
    static let fullA = Template(name: "Full body A", slots: [
        Slot(.squat, 8, "back-squat", "leg-press", "goblet-squat", "bw-squat"),
        Slot(.horizontalPress, 8, "bench", "machine-press", "db-bench", "pushup"),
        Slot(.verticalPull, 10, "pulldown", "db-pullover", "pullup"),
        Slot(.hamstringIsolation, 12, "leg-curl", "nordic"),
        Slot(.shoulderIsolation, 15, "lateral-raise", "cable-lateral"),
        Slot(.tricep, 12, "pushdown", "overhead-ext", "chair-dip"),
    ])

    static let fullB = Template(name: "Full body B", slots: [
        Slot(.hinge, 10, "bb-rdl", "db-rdl", "back-ext", "sl-rdl"),
        Slot(.horizontalPress, 10, "incline-machine", "db-incline", "decline-pushup"),
        Slot(.horizontalPull, 10, "chest-row", "db-chest-row", "inverted-row"),
        Slot(.lunge, 12, "bulgarian", "db-lunge", "bw-split-squat"),
        Slot(.verticalPress, 10, "machine-shoulder", "db-shoulder", "pike-pushup"),
        Slot(.bicep, 12, "db-curl", "bb-curl", "chin-up"),
    ])

    // MARK: - The week

    /// Which sessions somebody runs, from how many days they said they train.
    ///
    /// Two days is two full body days, because half an upper/lower rotation twice a week
    /// trains each half once a fortnight. Five is push/pull/legs plus upper/lower, which
    /// is the standard way to get a sixth and seventh session's worth of volume into
    /// five days. Six is push/pull/legs twice, which hits everything twice a week.
    static func week(for frequency: TrainingFrequency) -> [Template] {
        switch frequency {
        case .rarely: return [fullA, fullB]
        case .few:    return [upper, lower]
        case .most:   return [push, pull, legs, upper, lower]
        case .daily:  return [push, pull, legs]
        }
    }

    /// What the split is called, which is what somebody recognises it by.
    static func name(for frequency: TrainingFrequency) -> String {
        switch frequency {
        case .rarely: return "Full body"
        case .few:    return "Upper / lower"
        case .most:   return "Push / pull / legs + upper / lower"
        case .daily:  return "Push / pull / legs"
        }
    }
}
