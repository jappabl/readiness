import Foundation
import Testing
@testable import ReadinessCore

@Suite("Reviewed food and weight logs")
struct FoodLogTests {
    @Test func badNumbersCannotBecomeSavedMeals() {
        #expect(!MealNutrition(calories: .nan, protein: 20, carbs: 30, fat: 10).isValid)
        #expect(!MealNutrition(calories: 400, protein: -1, carbs: 30, fat: 10).isValid)
        #expect(!MealNutrition(calories: 400, protein: 20, carbs: .infinity, fat: 10).isValid)
        #expect(MealNutrition(calories: 400, protein: 20, carbs: 30, fat: 10).isValid)
    }
    /// Was `modelOutputMustBeCompleteAndReviewable`, which required all four numbers.
    /// Relaxed after a photo of an avocado came back named and calorie-counted but
    /// without macros, and the whole estimate was discarded. A name and calories are
    /// what make an estimate reviewable; the macros are detail the person can fill in,
    /// and nothing reaches the log without them reading it back first.
    @Test func modelOutputMustBeNamedAndCaloriedToBeReviewable() throws {
        let good = Data(#"{"name":"Chicken bowl","calories":540,"protein":42,"carbs":55,"fat":16}"#.utf8)
        #expect(try MealEstimate.decode(good).name == "Chicken bowl")
        // Still rejected: nothing to review without a name or a calorie figure.
        #expect(throws: (any Error).self) { try MealEstimate.decode(Data(#"{"name":"","calories":500,"protein":0,"carbs":0,"fat":0}"#.utf8)) }
        #expect(throws: (any Error).self) { try MealEstimate.decode(Data(#"{"name":"Food"}"#.utf8)) }
        // Now kept, and surfaced for correction rather than thrown away.
        #expect(try MealEstimate.decode(Data(#"{"name":"Food","calories":500}"#.utf8)).calories == 500)
    }
    @Test func bodyMassConversionsRoundTripWithoutChangingStoredUnit() {
        let pounds = BodyMass.display(kilograms: 80, metric: false)
        #expect(abs(pounds - 176.3698) < 0.001)
        #expect(abs(BodyMass.kilograms(display: pounds, metric: false) - 80) < 0.0001)
        #expect(!BodyMass.isValid(kilograms: .infinity))
        #expect(!BodyMass.isValid(kilograms: 0))
    }
}


@Suite("Strict meal number entry")
struct FoodNumberTests {
    @Test func parsesDecimalValuesInTheChosenLocale() {
        #expect(FoodNumber.parse("120", decimalSeparator: ".") == 120)
        #expect(FoodNumber.parse("12.5", decimalSeparator: ".") == 12.5)
        #expect(FoodNumber.parse("12,5", decimalSeparator: ",") == 12.5)
        #expect(FoodNumber.parse(" 0,5 ", decimalSeparator: ",") == 0.5)
        #expect(FoodNumber.parse(".5", decimalSeparator: ".") == 0.5)
        #expect(FoodNumber.parse("0", decimalSeparator: ".") == 0)
    }

    @Test func rejectsPartialNumbersAndGrouping() {
        for text in ["120abc", "120 kcal", "120 999", "1.2.3", "1,5", "1,000", "", ".", "NaN", "inf", "1e4"] {
            #expect(FoodNumber.parse(text, decimalSeparator: ".") == nil, "Accepted: \(text)")
        }
        for text in ["1.5", "1.000", "1,2,3", "1 000", "1,000.5"] {
            #expect(FoodNumber.parse(text, decimalSeparator: ",") == nil, "Accepted: \(text)")
        }
        #expect(FoodNumber.parse(String(repeating: "9", count: 400), decimalSeparator: ".") == nil)
    }

    @Test func parsedNegativeNutritionStillFailsValidation() {
        let negative = FoodNumber.parse("-1.5", decimalSeparator: ".")
        #expect(negative == -1.5)
        #expect(!MealNutrition(calories: negative ?? 0, protein: 0, carbs: 0, fat: 0).isValid)
    }
}

/// A photo estimate is a guess from a language model, and models do not return one
/// tidy shape. An avocado came back with no macros and the whole estimate was thrown
/// away, which showed the user "couldn't get a complete estimate" for a photo that had
/// been read correctly.
@Suite("Reading a model's meal estimate")
struct MealEstimateDecodingTests {

    @Test("the tidy shape still works")
    func fullNumbers() throws {
        let estimate = try MealEstimate.decode(Data(#"{"name":"Avocado","calories":240,"protein":3,"carbs":13,"fat":22}"#.utf8))
        #expect(estimate.name == "Avocado")
        #expect(estimate.calories == 240)
        #expect(estimate.protein == 3)
    }

    @Test("calories without macros is kept, not thrown away")
    func caloriesOnly() throws {
        let estimate = try MealEstimate.decode(Data(#"{"name":"Avocado","calories":240}"#.utf8))
        #expect(estimate.calories == 240)
        // Unknown, shown as zero for the user to correct. The flow requires a review
        // before anything is logged, so a blank is a prompt rather than a claim.
        #expect(estimate.protein == 0)
        #expect(estimate.carbs == 0)
        #expect(estimate.fat == 0)
    }

    @Test("numbers quoted as strings are read as numbers")
    func stringNumbers() throws {
        let estimate = try MealEstimate.decode(Data(#"{"name":"Avocado","calories":"240","protein":"3","carbs":"13","fat":"22"}"#.utf8))
        #expect(estimate.calories == 240)
        #expect(estimate.fat == 22)
    }

    @Test("nulls are read as unknown rather than as a failure")
    func nullMacros() throws {
        let estimate = try MealEstimate.decode(Data(#"{"name":"Avocado","calories":240,"protein":null,"carbs":null,"fat":null}"#.utf8))
        #expect(estimate.calories == 240)
        #expect(estimate.protein == 0)
    }

    @Test("a range is read as its midpoint, because models hedge")
    func rangeValue() throws {
        let estimate = try MealEstimate.decode(Data(#"{"name":"Avocado","calories":"160-240","protein":3,"carbs":13,"fat":22}"#.utf8))
        #expect(estimate.calories == 200)
    }

    @Test("no food found stays a separate outcome from a broken response")
    func emptyObject() {
        #expect(throws: MealEstimate.NoFoodFound.self) {
            try MealEstimate.decode(Data("{}".utf8))
        }
    }

    @Test("a response with no calories at all is still a failure")
    func missingCalories() {
        #expect(throws: (any Error).self) {
            try MealEstimate.decode(Data(#"{"name":"Avocado"}"#.utf8))
        }
    }
}

/// What somebody actually types into a meal.
///
/// A tester entered a name, 200 kcal and 20g of protein and watched the Log meal button
/// stay grey for ever. Every macro had to parse or the whole meal was invalid, and a
/// blank box does not parse, so leaving carbs and fat alone made the meal unloggable
/// with nothing on screen saying so. He wrote that the button was decoration.
@Suite("Macros somebody left blank")
struct BlankMacroTests {
    private func macro(_ text: String) -> Double? {
        FoodNumber.macro(text, decimalSeparator: ".")
    }

    @Test func aBoxLeftAloneIsTheZeroItsPlaceholderShows() {
        #expect(macro("") == 0)
        #expect(macro("   ") == 0)
    }

    /// Blank and wrong are different answers. Reading "abc" as zero would log a meal
    /// somebody did not describe.
    @Test func somethingTypedStillHasToBeANumber() {
        #expect(macro("abc") == nil)
        #expect(macro("12g") == nil)
        #expect(macro("20") == 20)
        #expect(macro("20.5") == 20.5)
    }

    /// The calories are the one figure a meal cannot do without, and they go through the
    /// strict reading rather than this one.
    @Test func caloriesAreNotAMacro() {
        #expect(FoodNumber.parse("", decimalSeparator: ".") == nil)
    }

    /// The whole reason for the change: a meal with calories and protein and nothing else
    /// is a meal.
    @Test func calorieAndProteinOnlyIsAValidMeal() throws {
        let values = MealNutrition(calories: 200,
                                   protein: try #require(macro("20")),
                                   carbs: try #require(macro("")),
                                   fat: try #require(macro("")))
        #expect(values.isValid)
    }
}

/// The word on the button and the arithmetic behind it have to agree.
///
/// A tester rated every set of a session "Comfortable" and the summary told him "Hard
/// sets: 12". Comfortable was three reps in reserve, and three is inside the engine's own
/// line for a hard set, so every answer on offer counted as hard and the stat could never
/// read zero.
@Suite("Comfortable is not a hard set")
struct EffortLabelTests {

    private func set(rir: Int) -> LiftSet {
        LiftSet(load: 100, reps: 10, rir: rir, muscleGroup: .chest)
    }

    @Test func aComfortableSetIsNotCountedAsAHardOne() {
        let comfortable = StrainEngine.hardSetRIRThreshold + 1
        let load = StrainEngine.sessionLoad(sets: [set(rir: comfortable)], sessionRPE: 5)
        #expect(load.hardSetsByMuscle.values.reduce(0, +) == 0)
        #expect(load.closeToFailureShare == 0)
    }

    @Test func hardAndAllOutStillAre() {
        let load = StrainEngine.sessionLoad(sets: [set(rir: 1), set(rir: 0)], sessionRPE: 8)
        #expect(load.hardSetsByMuscle[.chest] == 2)
        #expect(load.closeToFailureShare == 1)
    }
}

/// The word on the button and the arithmetic behind it, part two.
///
/// Comfortable was moved outside the hard-set threshold, and the logger still
/// preselected the button from the plan's own target of two reps in reserve. Two is
/// inside the threshold, so the screen said Comfortable and the engine counted a hard
/// set. A tester rated nothing, logged three sets and was told he had done three hard
/// ones.
@Suite("The button and the count agree")
struct EffortBucketTests {

    @Test("every answer the logger offers lands on the right side of the line",
          arguments: StrainEngine.Effort.allCases)
    func eachAnswerIsConsistentWithItsOwnName(effort: StrainEngine.Effort) {
        #expect(StrainEngine.effort(forRIR: effort.rawValue) == effort,
                "\(effort.title) does not map back to itself")
        #expect(effort.isHardSet == (effort != .comfortable))
    }

    /// The plan's own target for an experienced lifter is two, which is hard work, and
    /// the preselected button has to say so.
    @Test func aplanWrittenAtTwoRepsInReserveReadsAsHard() {
        #expect(StrainEngine.effort(forRIR: 2) == .hard)
        #expect(StrainEngine.effort(forRIR: 3) == .hard)
    }

    @Test func onlyRealSlackIsComfortable() {
        #expect(StrainEngine.effort(forRIR: 4) == .comfortable)
        #expect(StrainEngine.effort(forRIR: 8) == .comfortable)
    }

    @Test func nothingLeftIsAllOut() {
        #expect(StrainEngine.effort(forRIR: 0) == .allOut)
        #expect(StrainEngine.effort(forRIR: -2) == .allOut, "a nonsense value is not comfortable")
    }
}
