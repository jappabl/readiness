import Foundation
import Testing
@testable import ReadinessCore

@Suite("Jett's first conversation")
struct OnboardingConversationTests {
    @Test func openingAsksOneQuestion() {
        let flow = OnboardingConversation()
        #expect(flow.step == .goal)
        #expect(flow.turns.count == 2)
        #expect(flow.latestEditableAnswerID == nil)
    }

    @Test(arguments: TrainingGoal.allCases)
    func everyGoalReachesFrequency(_ goal: TrainingGoal) {
        var flow = OnboardingConversation()
        flow.toggleGoal(goal); flow.confirmGoals()
        #expect(flow.answers.goal == goal)
        #expect(flow.step == .frequency)
        #expect(flow.turns[2].text == goal.title)
        #expect(flow.turns.count == 4, "One short Jett response follows the answer")
        let count = flow.turns.count
        flow.toggleGoal(.feelBetter); flow.confirmGoals()
        #expect(flow.turns.count == count, "Double taps cannot answer the next question")
    }

    @Test(arguments: TrainingFrequency.allCases)
    func frequencyAndOptionalObstacles(_ frequency: TrainingFrequency) {
        var flow = OnboardingConversation()
        flow.toggleGoal(.getStronger); flow.confirmGoals()
        flow.chooseFrequency(frequency)
        flow.chooseExperience(.regular)
        flow.confirmObstacles()
        flow.confirmLimitations(none: true)
        flow.chooseEquipment(.fullGym)
        #expect(flow.answers.frequency == frequency)
        #expect(flow.answers.obstacles.isEmpty)
        #expect(flow.step == .units)
        #expect(flow.turns.contains { $0.text == "Nothing to add" })
    }

    @Test func editsOnlyLastAnswerAndDropsItsFollowup() {
        var flow = OnboardingConversation()
        flow.toggleGoal(.getStronger); flow.confirmGoals()
        let old = flow.latestEditableAnswerID!
        flow.chooseFrequency(.few)
        let last = flow.latestEditableAnswerID!
        flow.editAnswer(id: old)
        #expect(flow.step == .experience)
        flow.editAnswer(id: last)
        #expect(flow.step == .frequency)
        #expect(flow.turns.last?.text.contains("How many days a week") == true)
        flow.chooseFrequency(.daily)
        #expect(flow.answers.frequency == .daily)
        #expect(!flow.turns.contains { $0.text == "3–4 days a week" })
    }

    @Test func selectedObstaclesSurviveEditingInStableOrder() {
        var flow = readyForObstacles()
        flow.toggleObstacle(.time)
        flow.toggleObstacle(.sleep)
        flow.confirmObstacles()
        #expect(flow.turns.contains { $0.text == "Not sleeping enough, Not enough time" })
        flow.editAnswer(id: flow.latestEditableAnswerID!)
        #expect(flow.answers.obstacles == [.time, .sleep])
        flow.toggleObstacle(.time)
        flow.confirmObstacles()
        #expect(flow.answers.obstacles == [.sleep])
    }

    @Test func healthLocksAnswersAndEmptyReadStillFinishes() {
        var flow = readyForObstacles()
        flow.confirmObstacles()
        flow.confirmLimitations(none: true)
        flow.chooseUnits(metric: true)
        flow.chooseWatch(wearsOne: true)
        #expect(flow.step == .health)
        #expect(flow.answers.isComplete)
        let answer = flow.latestEditableAnswerID!
        flow.beginReading()
        flow.editAnswer(id: answer)
        #expect(flow.step == .reading)
        #expect(flow.latestEditableAnswerID == nil)
        flow.finishReading(hasHealthData: false)
        if flow.step == .weight { flow.skipWeight() }
        if flow.step == .notifications { flow.chooseNotifications(allowed: true) }
        #expect(flow.step == .healthDetails)
        flow.skipHealthDetails()
        flow.skipWeight()
        flow.chooseNotifications(allowed: true)
        #expect(flow.step == .ready)
        #expect(flow.answers.healthDetails == nil)
    }

    @Test(arguments: [true, false])
    func healthResultStaysShortAndNeverPromisesHRV(_ hasData: Bool) {
        var flow = readyForObstacles()
        flow.confirmObstacles()
        flow.confirmLimitations(none: true)
        flow.chooseUnits(metric: true)
        flow.chooseWatch(wearsOne: true)
        flow.beginReading()
        let before = flow.turns.count
        flow.finishReading(hasHealthData: hasData)
        if flow.step == .weight { flow.skipWeight() }
        if flow.step == .notifications { flow.chooseNotifications(allowed: true) }
        #expect(flow.turns.count == before + 1)
        for turn in flow.turns where !turn.isUser {
            #expect(turn.text.split(separator: " ").count <= 28)
            #expect(!turn.text.contains("[chart:"))
            #expect(!turn.text.contains("baseline"))
            #expect(!turn.text.contains("HRV"))
        }
    }

    private func readyForObstacles() -> OnboardingConversation {
        var flow = OnboardingConversation()
        flow.toggleGoal(.feelBetter); flow.confirmGoals()
        flow.chooseFrequency(.few)
        flow.chooseExperience(.regular)
        return flow
    }
}

extension OnboardingConversationTests {
    @Test func emptyHealthContextDoesNotInventMeasurements() {
        let context = CoachContextBuilder.withoutHealth(today: .now, goal: "feelBetter")
        #expect(context.state == "unknown")
        #expect(context.confidence == "none")
        #expect(context.daysOfHistory == 0)
        #expect(context.metrics.isEmpty)
        #expect(context.proposedAdjustments.isEmpty)
        #expect(context.goal == "feelBetter")
    }
}


extension OnboardingConversationTests {
    /// Two reactions in the whole conversation, and both are earned.
    ///
    /// They used to land on nearly every answer: a heart for saying you are new, a thumbs
    /// up for three days a week. A tester read them as decoration he had not added and
    /// that did not mean anything, which is what a reaction becomes when it arrives
    /// whatever you said.
    @Test func jettReactsToWhatIsWorthReactingToAndNothingElse() {
        var strength = OnboardingConversation()
        strength.toggleGoal(.getStronger); strength.confirmGoals()
        #expect(strength.turns.first { $0.isUser }?.reaction == .muscle)
        strength.chooseFrequency(.daily)
        #expect(strength.turns.last { $0.isUser }?.reaction == .running)

        // Feeling better is not a flex and two days a week is not a marathon, so neither
        // gets a badge. The sentence Jett replies with is where the warmth goes.
        var health = OnboardingConversation()
        health.toggleGoal(.feelBetter); health.confirmGoals()
        #expect(health.turns.first { $0.isUser }?.reaction == nil)
        health.chooseFrequency(.few)
        #expect(health.turns.last { $0.isUser }?.reaction == nil)
        health.chooseExperience(.regular)
        #expect(health.turns.last { $0.isUser }?.reaction == nil)
        health.toggleObstacle(.stress)
        health.confirmObstacles()
        #expect(health.turns.last { $0.isUser }?.reaction == nil)
        health.confirmLimitations(none: true)
        health.chooseUnits(metric: true)
        health.chooseWatch(wearsOne: true)
        #expect(health.turns.last { $0.isUser }?.reaction == nil)
    }

    /// Nothing in the way is an answer, not a question left blank, and it is given the
    /// same way as "None" on the injuries question right after it. The two used to
    /// disagree: a Skip in the footer of one, a None among the choices of the other.
    @Test func nothingInTheWayIsAnAnswerLikeAnyOther() {
        var flow = readyForObstacles()
        flow.toggleObstacle(.sleep)
        flow.confirmObstacles(none: true)
        #expect(flow.answers.obstacles.isEmpty)
        #expect(flow.turns.last { $0.isUser }?.text == "Nothing to add")
        #expect(flow.turns.last?.text.contains("clear runway") == true)
    }
}


extension OnboardingConversationTests {
    @Test func multipleGoalsGetAnAcknowledgement() {
        var flow = OnboardingConversation()
        for goal in TrainingGoal.allCases { flow.toggleGoal(goal) }
        flow.confirmGoals()
        #expect(flow.turns.last?.text.contains("whole upgrade") == true)
        #expect(flow.turns.last?.text.contains("week") == true)
    }
    @Test func lowFrequencyNoviceGetsReassuranceNotPressure() {
        var flow = OnboardingConversation()
        flow.toggleGoal(.getStronger); flow.confirmGoals()
        flow.chooseFrequency(.rarely)
        #expect(flow.turns.last?.text.contains("room for life") == true)
        flow.chooseExperience(.new)
        #expect(flow.turns.last?.text.contains("No catching up") == true)
    }
    @Test func sleepStressAndFoodAreAcknowledgedWithoutCelebrating() {
        var flow = readyForObstacles()
        flow.toggleObstacle(.sleep); flow.toggleObstacle(.stress); flow.toggleObstacle(.nutrition)
        flow.confirmObstacles()
        #expect(flow.turns.last { $0.isUser }?.reaction == nil)
        let text = flow.turns.last?.text.lowercased() ?? ""
        #expect(text.contains("sleep") && text.contains("stress") && text.contains("meals"))
        flow.confirmLimitations(none: true)
        #expect(flow.turns.last?.text.contains("Good to know") == true)
    }
}

/// The reveal was specified in the brief and never built: the flow went from connecting
/// Health straight to "You're set", skipping the one moment where Jett shows the user
/// their own data. It is the payoff for everything they just answered, and the only
/// place in onboarding where a chart earns its space.
@Suite("The reveal")
struct OnboardingRevealTests {

    private func atReading(days: Int) -> OnboardingConversation {
        var flow = OnboardingConversation()
        flow.toggleGoal(.getStronger); flow.confirmGoals()
        flow.chooseFrequency(.few)
        flow.chooseExperience(.regular)
        flow.confirmObstacles()
        flow.confirmLimitations(none: true)
        flow.chooseEquipment(.fullGym)
        flow.chooseUnits(metric: false)
        flow.chooseWatch(wearsOne: true)
        flow.beginReading()
        return flow
    }

    @Test("it states the real number of days read")
    func statesTheCount() {
        var flow = atReading(days: 179)
        flow.finishReading(hasHealthData: true, daysRead: 179)
        if flow.step == .weight { flow.skipWeight() }
        if flow.step == .notifications { flow.chooseNotifications(allowed: true) }
        let said = flow.turns.map(\.text).joined(separator: " | ")
        #expect(said.contains("179"))
    }

    @Test("the reveal carries a chart, and nothing else in the flow does")
    func onlyTheRevealCharts() {
        var flow = atReading(days: 179)
        flow.finishReading(hasHealthData: true, daysRead: 179)
        if flow.step == .weight { flow.skipWeight() }
        if flow.step == .notifications { flow.chooseNotifications(allowed: true) }
        let charted = flow.turns.filter { $0.chart != nil }
        #expect(charted.count == 1)
        #expect(charted.first?.isUser == false)
    }

    @Test("with no history there is no chart and no invented number")
    func noDataNoChart() {
        var flow = atReading(days: 0)
        flow.finishReading(hasHealthData: false, daysRead: 0)
        if flow.step == .weight { flow.skipWeight() }
        if flow.step == .notifications { flow.chooseNotifications(allowed: true) }
        #expect(flow.turns.allSatisfy { $0.chart == nil })
        let said = flow.turns.map(\.text).joined(separator: " | ")
        #expect(!said.contains("0 days"))
        #expect(!said.contains("0 nights"))
    }

    @Test("one night is not 1 nights")
    func singularReads() {
        var flow = atReading(days: 1)
        flow.finishReading(hasHealthData: true, daysRead: 1)
        if flow.step == .weight { flow.skipWeight() }
        if flow.step == .notifications { flow.chooseNotifications(allowed: true) }
        let said = flow.turns.map(\.text).joined(separator: " | ")
        #expect(said.contains("1 night"))
        #expect(!said.contains("1 nights"))
    }

    @Test("a complete profile goes straight from the reveal to taking a question")
    func endsReady() {
        var flow = atReading(days: 179)
        let known = HealthProfile(heightCM: 178,
                                  dateOfBirth: DateComponents(year: 1998, month: 4, day: 2),
                                  biologicalSex: .male)
        flow.finishReading(hasHealthData: true, daysRead: 179, profile: known)
        if flow.step == .weight { flow.skipWeight() }
        if flow.step == .notifications { flow.chooseNotifications(allowed: true) }
        #expect(flow.step == .ready)
    }

    @Test("a profile with gaps still reveals first, then asks for the gaps")
    func revealComesBeforeTheGaps() {
        var flow = atReading(days: 179)
        flow.finishReading(hasHealthData: true, daysRead: 179)
        if flow.step == .weight { flow.skipWeight() }
        if flow.step == .notifications { flow.chooseNotifications(allowed: true) }
        #expect(flow.step == .healthDetails)
        // The reveal is not skipped just because something else needs asking.
        #expect(flow.turns.contains { $0.chart != nil })
    }

    /// The reveal under this sentence needs seven readings before it can place anybody in
    /// their own range, so below that it renders nothing, and "that's your normal now"
    /// landed over an empty space for every watch bought this week.
    @Test("a normal is only claimed once there is one to show",
          arguments: [1, 3, 6])
    func noNormalClaimedTooEarly(days: Int) {
        var flow = atReading(days: days)
        flow.finishReading(hasHealthData: true, daysRead: days)
        if flow.step == .weight { flow.skipWeight() }
        if flow.step == .notifications { flow.chooseNotifications(allowed: true) }
        let said = flow.turns.map(\.text).joined(separator: " ")
        #expect(!said.contains("That's your normal now"),
                "claimed a normal off \(days) days")
        #expect(said.contains("\(days)"), "never said how much it had")
    }

    @Test("and is claimed once there is", arguments: [7, 30, 180])
    func normalClaimedWhenEarned(days: Int) {
        var flow = atReading(days: days)
        flow.finishReading(hasHealthData: true, daysRead: days)
        if flow.step == .weight { flow.skipWeight() }
        if flow.step == .notifications { flow.chooseNotifications(allowed: true) }
        #expect(flow.turns.map(\.text).joined().contains("That's your normal now"))
    }
}

/// A half-answered conversation has to survive being written down.
///
/// It used to die with the app. A tester force quit twice while stuck on a question and
/// came back both times to "Hey, I'm Jett" with eight answers gone, which is the point
/// most people delete an app rather than answer it all a third time.
@Suite("Onboarding survives being put down")
struct OnboardingDraftTests {

    private func halfway() -> OnboardingConversation {
        var flow = OnboardingConversation()
        flow.toggleGoal(.getStronger); flow.confirmGoals()
        flow.chooseFrequency(.most)
        flow.chooseExperience(.regular)
        flow.toggleObstacle(.sleep); flow.confirmObstacles()
        return flow
    }

    private func roundTrip(_ flow: OnboardingConversation) throws -> OnboardingConversation {
        let data = try JSONEncoder().encode(flow)
        return try JSONDecoder().decode(OnboardingConversation.self, from: data)
    }

    @Test func everyAnswerAndEveryWordComesBack() throws {
        let before = halfway()
        let after = try roundTrip(before)
        #expect(after.step == before.step)
        #expect(after.turns.map(\.text) == before.turns.map(\.text))
        #expect(after.turns.map(\.reaction) == before.turns.map(\.reaction))
        #expect(after.answers == before.answers)
    }

    /// Coming back has to leave somebody able to carry on, not just able to read what
    /// they said. The conversation's own bookkeeping travels with it.
    @Test func theConversationCarriesOnFromWhereItStopped() throws {
        var after = try roundTrip(halfway())
        after.confirmLimitations(none: true)
        #expect(after.step == .equipment)
        after.chooseEquipment(.fullGym)
        #expect(after.answers.equipment == .fullGym)
    }

    /// Including the one piece of bookkeeping that is not an answer: which turn can still
    /// be changed. Losing it would leave a resumed conversation with no way back.
    @Test func theLastAnswerIsStillEditableAfterwards() throws {
        let before = halfway()
        let after = try roundTrip(before)
        #expect(after.latestEditableAnswerID == before.latestEditableAnswerID)
        var edited = after
        let id = try #require(after.latestEditableAnswerID)
        edited.editAnswer(id: id)
        #expect(edited.step == .obstacles)
        #expect(edited.turns.count < after.turns.count)
    }

    /// A conversation that reached the health read is mid-task rather than mid-question,
    /// and the fields it is waiting on are part of what has to come back with it.
    @Test func whatTheHealthReadWasMissingSurvivesToo() throws {
        var flow = halfway()
        flow.confirmLimitations(none: true)
        flow.chooseEquipment(.fullGym)
        flow.chooseUnits(metric: false)
        flow.chooseWatch(wearsOne: true)
        flow.beginReading()
        flow.finishReading(hasHealthData: true, daysRead: 30,
                           profile: HealthProfile(), today: Date())
        let after = try roundTrip(flow)
        #expect(after.missingHealthFields == flow.missingHealthFields)
        #expect(after.step == flow.step)
    }
}
