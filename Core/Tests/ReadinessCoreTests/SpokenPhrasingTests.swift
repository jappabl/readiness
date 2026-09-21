import Testing
@testable import ReadinessCore

/// Every way somebody actually says a set out loud.
///
/// Built from a real failure: "I did 3 sets of 155 of bench press 6 reps per", said to
/// Siri on a phone, came back as "I didn't catch any sets in that". Three things were
/// wrong at once, and finding them one at a time would have taken three more attempts,
/// so the whole space got swept instead.
///
/// The table is the point. A parser like this is a pile of patterns that each look
/// reasonable and collectively disagree, and the only way to know it still works after a
/// change is to read what it does to fifty sentences rather than to three.
@Suite("Every way somebody says a set")
struct SpokenPhrasingTests {

    private let known = ["Bench press", "Back squat", "Overhead press", "Pull-up"]

    private func heard(_ text: String) -> (reps: [Int], load: Double?, rir: Int?) {
        let log = SpokenSetParser.parse(text, knownExercises: known)
        return (log?.reps ?? [], log?.load, log?.rir)
    }

    // MARK: - One set

    @Test("one set, however it is phrased", arguments: [
        "bench press 225 for 8",
        "225 for 8",
        "just did 8 at 225",
        "knocked out 8 at 225",
        "one set of 8 at 225",
        "8 reps at 225",
        "225 x 8",
        "225 by 8",
        "bench 225x8",
        "bench 225 8 reps",
        "logged 8 reps of bench at 225",
        "bench press, 225, 8",
        "225 8",
        "eight at two twenty five",
        "did eight reps with two twenty five on bench",
        "put up 225 eight times",
        "yeah did bench today, 225 for 8",
        "felt strong, bench 225 for 8",
    ])
    func oneSet(_ text: String) {
        let result = heard(text)
        #expect(result.reps == [8], "\(text) gave \(result.reps)")
        #expect(result.load == 225, "\(text) gave \(String(describing: result.load))")
    }

    // MARK: - Several sets, same reps

    @Test("three sets of eight at 225, however it is phrased", arguments: [
        "3 sets of 8 at 225",
        "3x8 at 225",
        "3x8 225",
        "bench 3 sets of 8 at 225",
        "uh so I think I did like 3 sets of 8 on bench at 225",
        "finished bench press three by eight at two twenty five",
        "8 reps at 225 for 3 sets",
        "225 for 8, three sets",
        "three sets of eight reps at two twenty five pounds",
    ])
    func threeSets(_ text: String) {
        let result = heard(text)
        #expect(result.reps == [8, 8, 8], "\(text) gave \(result.reps)")
        #expect(result.load == 225, "\(text) gave \(String(describing: result.load))")
    }

    // MARK: - Sets that went differently

    @Test("a run that dropped off is kept in full", arguments: [
        "225 for 8, 7, 6",
        "8, 7, 6 at 225",
        "bench press 225 for 8, 7 and 6",
    ])
    func decliningReps(_ text: String) {
        #expect(heard(text).reps == [8, 7, 6], "\(text) gave \(heard(text).reps)")
    }

    // MARK: - Weights said out loud

    @Test("the weight, in words", arguments: [
        ("one hundred kilos for five", 100.0),
        ("two twenty five for eight", 225.0),
        ("a hundred and thirty five for ten", 135.0),
        ("ninety five for twelve", 95.0),
        ("three fifteen for three", 315.0),
        ("four oh five for one", 405.0),
    ])
    func spokenWeights(_ text: String, _ expected: Double) {
        #expect(heard(text).load == expected, "\(text) gave \(String(describing: heard(text).load))")
    }

    @Test("units, however they are said", arguments: [
        "100 kilos for 5", "100 kg for 5", "100 kilograms for 5",
    ])
    func metricUnits(_ text: String) {
        let log = SpokenSetParser.parse(text)
        #expect(log?.load == 100)
        #expect(log?.loadUnit == .kilograms, "\(text) lost its unit")
    }

    // MARK: - Effort

    @Test("what was left in the tank is not a rep count", arguments: [
        ("225 for 5, 3 RIR", 3),
        ("bench 225 for 5, left 2 in the tank", 2),
        ("225 for 5 with 3 reps in reserve", 3),
        ("squat 225 for 5, that was all out", 0),
        ("225 for 5 to failure", 0),
    ])
    func effortIsNotReps(_ text: String, _ expected: Int) {
        let result = heard(text)
        #expect(result.reps == [5], "\(text) gave \(result.reps)")
        #expect(result.rir == expected, "\(text) gave \(String(describing: result.rir))")
    }

    // MARK: - Nothing to weigh

    @Test("bodyweight work is reps and no load", arguments: [
        ("20 push ups", [20]),
        ("did 15 pull-ups", [15]),
        ("pull-up 8 reps", [8]),
        ("did a set of 10 on bench", [10]),
    ])
    func bodyweight(_ text: String, _ expected: [Int]) {
        let result = heard(text)
        #expect(result.reps == expected, "\(text) gave \(result.reps)")
        #expect(result.load == nil, "\(text) invented \(String(describing: result.load))")
    }

    @Test("three sets of twelve, no weight named")
    func bodyweightSets() {
        let result = heard("did 3 sets of 12 push ups")
        #expect(result.reps == [12, 12, 12])
        #expect(result.load == nil)
    }

    // MARK: - The sentence that started it

    @Test("the one that came back empty from a real phone")
    func theOriginalFailure() {
        let result = heard("I did 3 sets of 155 of bench press 6 reps per")
        #expect(result.reps == [6, 6, 6])
        #expect(result.load == 155)
    }

    // MARK: - Nothing said

    @Test("noise is still refused", arguments: [
        "", "uh", "yeah ok", "that was good", "hello",
    ])
    func silence(_ text: String) {
        let log = SpokenSetParser.parse(text, knownExercises: known)
        #expect(log?.reps.isEmpty ?? true, "\(text) invented \(log?.reps ?? [])")
    }
}
