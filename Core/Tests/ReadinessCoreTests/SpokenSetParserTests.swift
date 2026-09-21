import Testing
@testable import ReadinessCore

@Suite("Hearing a set")
struct SpokenSetParserTests {

    @Test("the headline case: sets, reps, effort and feel in one breath")
    func theWholeThing() {
        let log = SpokenSetParser.parse(
            "I did three sets of eight, six, seven, all to failure, felt heavy today")
        #expect(log?.reps == [8, 6, 7])
        #expect(log?.rir == 0)
        #expect(log?.feel == .heavy)
    }

    @Test("one rep count across several sets repeats it")
    func singleRepCountRepeats() {
        #expect(SpokenSetParser.parse("three sets of eight")?.reps == [8, 8, 8])
        #expect(SpokenSetParser.parse("2 sets of 10")?.reps == [10, 10])
    }

    @Test("the set count still counts when the lift's name comes between")
    func setCountSurvivesTheExerciseName() {
        // How people actually say it out loud: the name sits between the count and
        // the reps, so the two halves have to be heard separately.
        #expect(SpokenSetParser.parse("three sets of bench press at 165 for 5")?.reps
                == [5, 5, 5])
        #expect(SpokenSetParser.parse("4 sets of squats for 8")?.reps == [8, 8, 8, 8])
        #expect(SpokenSetParser.parse("two sets of deadlift 3x5")?.reps == [5, 5, 5])
    }

    /// Said to Siri on a real phone, and heard as nothing at all.
    ///
    /// Three things go wrong at once. "3 sets of 155" puts the weight where the parser
    /// expects the reps; 155 is not a plausible rep count so the whole list was discarded
    /// rather than reconsidered. "6 reps" is a shape the parser had no pattern for. And
    /// with no "at" and no "for" anywhere, every load pattern missed too, so a sentence
    /// naming the lift, the weight, the sets and the reps produced an empty result.
    @Test("the weight can sit where the reps usually do")
    func setsOfWeightThenRepsPer() {
        let log = SpokenSetParser.parse("I did 3 sets of 155 of bench press 6 reps per",
                                        knownExercises: ["Bench press"])
        #expect(log?.reps == [6, 6, 6])
        #expect(log?.load == 155)
        #expect(log?.exercise == "Bench press")
    }

    @Test("a bare rep count is heard")
    func bareRepsAreHeard() {
        #expect(SpokenSetParser.parse("bench press 225, 8 reps")?.reps == [8])
        #expect(SpokenSetParser.parse("4 sets of 185, 10 reps each")?.reps == [10, 10, 10, 10])
        #expect(SpokenSetParser.parse("squat 3 sets 5 reps")?.reps == [5, 5, 5])
    }

    @Test("a number too big to be reps is read as the weight")
    func impossibleRepCountIsAWeight() {
        let log = SpokenSetParser.parse("3 sets of 225")
        #expect(log?.load == 225)
        #expect(log?.reps.isEmpty == true, "no rep count was actually said")
    }

    @Test("a plausible rep count after sets of is still reps")
    func plausibleCountStaysReps() {
        // The existing reading must not be broken by the one above it.
        #expect(SpokenSetParser.parse("3 sets of 8")?.reps == [8, 8, 8])
        #expect(SpokenSetParser.parse("3 sets of 8")?.load == nil)
    }

    @Test("different reps across sets survive after for")
    func repListAfterFor() {
        // "155 for 6, 6, 5" is three sets that went differently, and only the first
        // was being kept. Losing the drop-off is losing the thing worth recording.
        #expect(SpokenSetParser.parse("bench press 155 for 6, 6, 5")?.reps == [6, 6, 5])
        #expect(SpokenSetParser.parse("225 for 8 and 7")?.reps == [8, 7])
    }

    @Test("a weight said last is still the weight")
    func trailingWeight() {
        // "back squat 5 reps 315". Nothing marks 315 as a load, but nobody does 315
        // reps either, and the rep count is already spoken for.
        let log = SpokenSetParser.parse("back squat 5 reps 315")
        #expect(log?.reps == [5])
        #expect(log?.load == 315)
    }

    @Test("one set stays one set")
    func oneSetStaysOne() {
        #expect(SpokenSetParser.parse("bench press at 165 for 5")?.reps == [5])
        #expect(SpokenSetParser.parse("one set of bench for 5")?.reps == [5])
    }

    @Test("digits and words are both heard")
    func digitsAndWords() {
        #expect(SpokenSetParser.parse("3 sets of 8, 6, 7")?.reps == [8, 6, 7])
        #expect(SpokenSetParser.parse("two sets of ten and twelve")?.reps == [10, 12])
    }

    @Test("weight is picked up however it is phrased")
    func loadIsHeard() {
        #expect(SpokenSetParser.parse("three sets of five at 225 pounds")?.load == 225)
        #expect(SpokenSetParser.parse("225 for 5")?.load == 225)
        #expect(SpokenSetParser.parse("did 185 lbs for 3 sets of 8")?.load == 185)
    }

    @Test("reps in reserve are heard in the language people use")
    func effortIsHeard() {
        #expect(SpokenSetParser.parse("three sets of five, all to failure")?.rir == 0)
        #expect(SpokenSetParser.parse("3 sets of 5, left two in the tank")?.rir == 2)
        #expect(SpokenSetParser.parse("3x5 with one rep in reserve")?.rir == 1)
        #expect(SpokenSetParser.parse("three sets of eight, went all out")?.rir == 0)
    }

    @Test("every feel word lands in one of the five buckets")
    func feelIsHeard() {
        #expect(SpokenSetParser.parse("felt heavy")?.feel == .heavy)
        #expect(SpokenSetParser.parse("that was brutal")?.feel == .grindy)
        #expect(SpokenSetParser.parse("moved fast")?.feel == .easy)
        #expect(SpokenSetParser.parse("felt smooth")?.feel == .smooth)
        #expect(SpokenSetParser.parse("sharp pain in my shoulder")?.feel == .painful)
    }

    @Test("an exercise is recognised when it is one of the user's own")
    func exerciseIsMatched() {
        let known = ["Back squat", "Romanian deadlift", "Bench press"]
        #expect(SpokenSetParser.parse("back squat three sets of five",
                                      knownExercises: known)?.exercise == "Back squat")
        #expect(SpokenSetParser.parse("did some bench press at 185",
                                      knownExercises: known)?.exercise == "Bench press")
    }

    @Test("an exercise the user does not have is not invented")
    func unknownExerciseIsNotInvented() {
        let log = SpokenSetParser.parse("did some zercher squats for 5",
                                        knownExercises: ["Back squat"])
        #expect(log?.exercise == nil)
    }

    @Test("speech with nothing loggable in it returns nothing")
    func nonsenseIsRejected() {
        #expect(SpokenSetParser.parse("what's the weather like") == nil)
        #expect(SpokenSetParser.parse("") == nil)
        #expect(SpokenSetParser.parse("   ") == nil)
    }

    @Test("absurd numbers are not accepted as reps or weight")
    func absurdNumbersRejected() {
        let log = SpokenSetParser.parse("three sets of nine hundred at 90000 pounds")
        #expect(log?.reps.allSatisfy { $0 <= SpokenSetParser.maximumReasonableReps } ?? true)
        #expect((log?.load ?? 0) <= SpokenSetParser.maximumReasonableLoad)
    }

    @Test("the transcript is kept verbatim so the user can see what was heard")
    func transcriptIsKept() {
        let said = "three sets of eight, felt heavy"
        #expect(SpokenSetParser.parse(said)?.transcript == said)
    }

    @Test("feel alone is worth logging even with no numbers")
    func feelAloneCounts() {
        let log = SpokenSetParser.parse("that felt really heavy")
        #expect(log?.feel == .heavy)
        #expect(log?.isEmpty == false)
    }
}
