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
