import Testing
@testable import ReadinessCore

/// Turning what was heard into sets that can be written down.
///
/// The parser reports what the words said; this decides what actually gets logged,
/// which lift, in which unit, with which effort when the sentence left it out.
@Suite("Resolving a dictated set")
struct SpokenSetResolverTests {

    private let bench = PlannedExercise(name: "Bench press", muscleGroup: .chest, sets: 3,
                                        reps: 5, workingWeight: 185, increment: 5, rir: 2)
    private let squat = PlannedExercise(name: "Back squat", muscleGroup: .quads, sets: 3,
                                        reps: 5, workingWeight: 275, increment: 10, rir: 2)

    private func resolve(_ said: String, current: PlannedExercise? = nil,
                         metric: Bool = false) -> SpokenSetResolver.Outcome {
        SpokenSetResolver.resolve(said, current: current, programme: [bench, squat],
                                  unitsAreMetric: metric)
    }

    @Test("the common case: a weight, a rep count, and the lift already on screen")
    func theCommonCase() throws {
        let resolved = try #require(resolve("225 for 8", current: bench).ready)
        #expect(resolved.exercise.name == "Bench press")
        #expect(resolved.sets.count == 1)
        #expect(resolved.sets.first?.load == 225)
        #expect(resolved.sets.first?.reps == 8)
        #expect(resolved.sets.first?.rir == 2, "the lift's own target, nobody said otherwise")
    }

    @Test("kilos said out loud are stored as pounds")
    func kilosConvert() throws {
        let resolved = try #require(resolve("100 kilos for 5", current: bench).ready)
        #expect(resolved.sets.first?.load == 100 * 2.2046226218)
    }

    @Test("a bare number is read in the unit the user thinks in")
    func bareNumberFollowsThePreference() throws {
        let metric = try #require(resolve("100 for 5", current: bench, metric: true).ready)
        #expect(metric.sets.first?.load == 100 * 2.2046226218)
        let imperial = try #require(resolve("100 for 5", current: bench).ready)
        #expect(imperial.sets.first?.load == 100)
    }

    @Test("pounds said by a metric user are still pounds")
    func spokenUnitBeatsThePreference() throws {
        let resolved = try #require(resolve("225 pounds for 5", current: bench, metric: true).ready)
        #expect(resolved.sets.first?.load == 225)
    }

    @Test("no weight said falls back to what the lift is programmed at")
    func loadFallsBackToTheProgramme() throws {
        let resolved = try #require(resolve("three sets of eight", current: bench).ready)
        #expect(resolved.sets.count == 3)
        #expect(resolved.sets.allSatisfy { $0.load == 185 })
        #expect(resolved.sets.allSatisfy { $0.reps == 8 })
    }

    @Test("naming a lift beats whatever is on screen")
    func namedLiftWins() throws {
        let resolved = try #require(resolve("back squat 315 for 3", current: bench).ready)
        #expect(resolved.exercise.name == "Back squat")
        #expect(resolved.sets.first?.load == 315)
    }

    @Test("to failure overrides the programmed effort")
    func failureOverridesRIR() throws {
        let resolved = try #require(resolve("225 for 8 to failure", current: bench).ready)
        #expect(resolved.sets.allSatisfy { $0.rir == 0 })
    }

    @Test("how it felt survives")
    func feelSurvives() throws {
        let resolved = try #require(resolve("225 for 8, felt grindy", current: bench).ready)
        #expect(resolved.feel == .grindy)
    }

    @Test("silence is not a set")
    func silenceLogsNothing() {
        #expect(resolve("", current: bench) == .heardNothing)
        #expect(resolve("uh, yeah", current: bench) == .heardNothing)
    }

    @Test("a sentence with no reps is a question, not a set")
    func noRepsAsks() {
        // "felt heavy" parses (feel alone is not nothing) but there is no set in it.
        #expect(resolve("felt heavy", current: bench) == .needsReps)
    }

    @Test("with nothing on screen and no lift named, ask which one")
    func noExerciseAsks() {
        #expect(resolve("225 for 8") == .needsExercise)
    }

    @Test("an unreasonable rep count is not quietly logged")
    func absurdRepsAreRefused() {
        // The parser already discards these, so nothing arrives to log.
        #expect(resolve("for 400", current: bench) == .heardNothing)
    }
}
