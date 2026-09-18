import Foundation

/// What the store already holds for a given day.
public struct PrescriptionSnapshot: Equatable, Sendable {
    public let id: UUID
    public let liftName: String
    /// True once something has actually been lifted against this prescription.
    public let hasOutcome: Bool

    public init(id: UUID, liftName: String, hasOutcome: Bool) {
        self.id = id
        self.liftName = liftName
        self.hasOutcome = hasOutcome
    }
}

public enum PrescriptionAction: Equatable, Sendable {
    case insert(liftName: String)
    case update(id: UUID)
    /// Already lifted against. Revising it after the fact would corrupt the grade.
    case freeze(id: UUID)
    case delete(id: UUID)
}

/// Decides how to reconcile today's prescriptions with what is already stored.
///
/// Exists because the obvious implementation — delete the day's rows and re-insert them —
/// hands every row a new identity and silently orphans the outcomes pointing at them.
public enum PrescriptionReconciler {
    public static func plan(existing: [PrescriptionSnapshot],
                            incoming: [String]) -> [PrescriptionAction] {
        let programmed = Set(incoming)
        var actions: [PrescriptionAction] = []

        for row in existing {
            if row.hasOutcome {
                actions.append(.freeze(id: row.id))
            } else if programmed.contains(row.liftName) {
                actions.append(.update(id: row.id))
            } else {
                actions.append(.delete(id: row.id))
            }
        }

        // A lift already holding a row for today — frozen or not — keeps it. Inserting
        // beside a frozen row would double-prescribe the same lift on the same day.
        let alreadyHeld = Set(existing.map(\.liftName).filter(programmed.contains))
        for name in incoming where !alreadyHeld.contains(name) {
            actions.append(.insert(liftName: name))
        }
        return actions
    }
}
