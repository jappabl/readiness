import Testing
@testable import ReadinessCore

@Suite("What the coach is allowed to ask for")
struct CoachToolsTests {

    @Test("each known action maps to the matching adjustment")
    func knownActionsMap() {
        #expect(CoachTools.adjustment(action: "reduce_sets", percent: 20, rir: nil)
                == .reduceWorkingSets(percent: 20))
        #expect(CoachTools.adjustment(action: "reduce_load", percent: 10, rir: nil)
                == .reduceLoad(percent: 10))
        #expect(CoachTools.adjustment(action: "cap_effort", percent: nil, rir: 4)
                == .capEffort(rir: 4))
        #expect(CoachTools.adjustment(action: "defer_lower_body", percent: nil, rir: nil)
                == .deferLowerBody)
        #expect(CoachTools.adjustment(action: "proceed_as_planned", percent: nil, rir: nil)
                == .proceedAsPlanned)
    }

    @Test("an action the app does not know is refused rather than guessed at")
    func unknownActionIsRefused() {
        #expect(CoachTools.adjustment(action: "delete_everything", percent: nil, rir: nil) == nil)
        #expect(CoachTools.adjustment(action: "", percent: nil, rir: nil) == nil)
    }

    @Test("an absurd set reduction is clamped, not obeyed")
    func setReductionIsClamped() {
        #expect(CoachTools.adjustment(action: "reduce_sets", percent: 500, rir: nil)
                == .reduceWorkingSets(percent: CoachTools.setReductionRange.upperBound))
        #expect(CoachTools.adjustment(action: "reduce_sets", percent: -30, rir: nil)
                == .reduceWorkingSets(percent: CoachTools.setReductionRange.lowerBound))
    }

    @Test("load cuts stay inside what the prescription engine will accept")
    func loadReductionRespectsTheFloor() {
        let clamped = CoachTools.adjustment(action: "reduce_load", percent: 90, rir: nil)
        guard case .reduceLoad(let percent) = clamped else {
            Issue.record("expected a load reduction"); return
        }
        #expect(Double(percent) / 100 <= abs(PrescriptionEngine.floorPercent))
    }

    @Test("an effort cap cannot be pushed past failure")
    func effortCapIsClamped() {
        #expect(CoachTools.adjustment(action: "cap_effort", percent: nil, rir: -5)
                == .capEffort(rir: 0))
        #expect(CoachTools.adjustment(action: "cap_effort", percent: nil, rir: 99)
                == .capEffort(rir: CoachTools.effortCapRange.upperBound))
    }

    @Test("a missing number falls back to a sensible default rather than failing")
    func missingNumbersDefault() {
        #expect(CoachTools.adjustment(action: "reduce_sets", percent: nil, rir: nil)
                == .reduceWorkingSets(percent: CoachTools.defaultSetReduction))
        #expect(CoachTools.adjustment(action: "reduce_load", percent: nil, rir: nil)
                == .reduceLoad(percent: CoachTools.defaultLoadReduction))
        #expect(CoachTools.adjustment(action: "cap_effort", percent: nil, rir: nil)
                == .capEffort(rir: CoachTools.defaultEffortCap))
    }

    @Test("whatever the model sends survives the session planner")
    func anyAcceptedCallProducesALoadableSession() {
        let lift = PlannedExercise(name: "Back squat", muscleGroup: .quads, sets: 4, reps: 5,
                                   workingWeight: 315, increment: 10, rir: 2)
        for action in ["reduce_sets", "reduce_load", "cap_effort", "defer_lower_body"] {
            for value in [-100, 0, 7, 1000] {
                guard let adjustment = CoachTools.adjustment(action: action,
                                                            percent: value, rir: value) else {
                    continue
                }
                let out = SessionPlanner.apply([adjustment], to: [lift])[0]
                #expect(out.sets >= 1, "\(action) \(value) left no sets")
                #expect(out.load >= lift.increment, "\(action) \(value) emptied the bar")
                #expect(out.rir >= lift.rir, "\(action) \(value) pushed closer to failure")
                let delta = lift.workingWeight - out.load
                #expect(abs(delta.truncatingRemainder(dividingBy: lift.increment)) < 1e-9)
            }
        }
    }

    @Test("the schema advertises exactly the actions the app implements")
    func schemaMatchesImplementation() {
        let properties = CoachTools.schema["input_schema"] as? [String: Any]
        let props = properties?["properties"] as? [String: Any]
        let action = props?["action"] as? [String: Any]
        let advertised = Set((action?["enum"] as? [String]) ?? [])
        for name in advertised {
            #expect(CoachTools.adjustment(action: name, percent: nil, rir: nil) != nil,
                    "schema advertises \(name) but the app cannot honour it")
        }
        #expect(advertised.count == 5)
    }
}
