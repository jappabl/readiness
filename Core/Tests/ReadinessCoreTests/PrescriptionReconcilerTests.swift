import Foundation
import Testing
@testable import ReadinessCore

private func snapshot(_ name: String, outcome: Bool = false) -> PrescriptionSnapshot {
    PrescriptionSnapshot(id: UUID(), liftName: name, hasOutcome: outcome)
}

@Suite("Reconciling today's prescriptions with what is already stored")
struct PrescriptionReconcilerTests {

    @Test("a lift with nothing stored yet is inserted")
    func newLiftIsInserted() {
        let plan = PrescriptionReconciler.plan(existing: [], incoming: ["Back squat"])
        #expect(plan == [.insert(liftName: "Back squat")])
    }

    @Test("an un-lifted prescription is updated in place, keeping its identity")
    func unloggedPrescriptionIsUpdated() {
        let row = snapshot("Back squat")
        let plan = PrescriptionReconciler.plan(existing: [row], incoming: ["Back squat"])
        #expect(plan == [.update(id: row.id)])
    }

    @Test("a prescription that has already been lifted against is frozen, not revised")
    func loggedPrescriptionIsFrozen() {
        let row = snapshot("Back squat", outcome: true)
        let plan = PrescriptionReconciler.plan(existing: [row], incoming: ["Back squat"])
        #expect(plan == [.freeze(id: row.id)])
    }

    @Test("a row for a lift no longer programmed is removed")
    func droppedLiftIsDeleted() {
        let row = snapshot("Overhead press")
        let plan = PrescriptionReconciler.plan(existing: [row], incoming: ["Back squat"])
        #expect(plan.contains(.delete(id: row.id)))
        #expect(plan.contains(.insert(liftName: "Back squat")))
    }

    @Test("a dropped lift that was already logged keeps its record")
    func droppedButLoggedLiftSurvives() {
        let row = snapshot("Overhead press", outcome: true)
        let plan = PrescriptionReconciler.plan(existing: [row], incoming: ["Back squat"])
        #expect(!plan.contains(.delete(id: row.id)),
                "deleting this would destroy an outcome that was actually recorded")
        #expect(plan.contains(.freeze(id: row.id)))
    }

    @Test("no plan ever deletes or rewrites a row carrying an outcome")
    func outcomesAreNeverOrphaned() {
        let logged = [snapshot("Back squat", outcome: true),
                      snapshot("Bench press", outcome: true)]
        let unlogged = [snapshot("Deadlift")]
        for incoming in [[], ["Back squat"], ["Deadlift", "Snatch"],
                         ["Back squat", "Bench press", "Deadlift"]] {
            let plan = PrescriptionReconciler.plan(existing: logged + unlogged, incoming: incoming)
            for row in logged {
                #expect(!plan.contains(.delete(id: row.id)), "deleted a graded row")
                #expect(!plan.contains(.update(id: row.id)), "rewrote a graded row")
            }
        }
    }

    @Test("every incoming lift is accounted for exactly once")
    func everyLiftIsHandledOnce() {
        let row = snapshot("Back squat")
        let plan = PrescriptionReconciler.plan(existing: [row],
                                               incoming: ["Back squat", "Bench press"])
        #expect(plan.filter { $0 == .update(id: row.id) }.count == 1)
        #expect(plan.filter { $0 == .insert(liftName: "Bench press") }.count == 1)
    }

    @Test("an empty program leaves graded history alone and clears the rest")
    func emptyProgramIsSafe() {
        let graded = snapshot("Back squat", outcome: true)
        let ungraded = snapshot("Bench press")
        let plan = PrescriptionReconciler.plan(existing: [graded, ungraded], incoming: [])
        #expect(plan.contains(.freeze(id: graded.id)))
        #expect(plan.contains(.delete(id: ungraded.id)))
    }
}
