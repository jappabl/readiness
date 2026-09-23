import Foundation

public enum CoachReaction: String, Codable, Sendable {
    case heart, like, muscle, running

    /// When Jett reacts to an answer, and to which ones.
    ///
    /// They used to land almost everywhere: a heart on "Just starting", a thumbs up on
    /// "3-4 days a week". A tester read them as decoration he had not added and that did
    /// not mean anything, which is what a reaction becomes when it arrives whatever you
    /// said. A reaction that is always there carries no information.
    ///
    /// So the rule is that Jett reacts where a person would and stays quiet otherwise.
    /// Three cases and no fourth:
    ///
    /// - 💪 when somebody says they want to get strong or big. That is the answer people
    ///   are pleased to give.
    /// - 🏃 when somebody says they train five, six or seven days a week. That is a
    ///   number worth acknowledging.
    ///
    /// Everything else gets nothing. Not the experience question, where hearting a
    /// beginner for being a beginner is a pat on the head, and not the two questions
    /// about what hurts and what is in the way: those answers cost something to give and
    /// are already met with a sentence that says so in words, which is worth more than a
    /// heart stuck on somebody's bad knee.
    public static func toGoals(_ goals: Set<TrainingGoal>) -> CoachReaction? {
        if goals.contains(.getStronger) || goals.contains(.buildMuscle) { return .muscle }
        return nil
    }

    public static func toFrequency(_ frequency: TrainingFrequency) -> CoachReaction? {
        frequency == .most || frequency == .daily ? .running : nil
    }

}

/// Scripted onboarding. No provider, timer or HealthKit dependency lives here.
public struct OnboardingConversation: Sendable, Codable {
    public enum Step: String, Sendable, Codable { case goal, frequency, experience, obstacles, limitations, equipment, pullUpBar, units, watch, health, reading, healthDetails, weight, notifications, ready }
    public struct Turn: Identifiable, Equatable, Sendable, Codable {
        public let id: Int
        public let isUser: Bool
        public let text: String
        public let reaction: CoachReaction?
        /// Set on the one turn that shows the user their own history. Talk goes in a
        /// bubble; a chart is content and is drawn full width beneath it.
        public var chart: MetricKind?
    }

    public private(set) var step: Step = .goal
    public private(set) var answers = OnboardingAnswers()
    public private(set) var turns: [Turn] = []
    public private(set) var missingHealthFields: [HealthProfile.Field] = []
    private var nextID = 0
    /// A struct rather than a tuple so the conversation can be written to disk. Half an
    /// answered onboarding used to die with the app: a tester force quit while stuck and
    /// came back to "Hey, I'm Jett" with every answer gone, twice.
    private struct LastAnswer: Sendable, Codable {
        let id: Int
        let step: Step
        let count: Int
    }
    private var lastAnswer: LastAnswer?

    public static let starterQuestions = [
        "How should I train this week?",
        "How can I recover better?",
        "How can I improve my sleep?",
        "What should I eat for my goal?",
    ]

    public init() {
        say("Hey, I'm Jett. I help with training, recovery, sleep, and nutrition.")
        say("What would you like to work on? Pick any that apply.")
    }

    public var latestEditableAnswerID: Int? {
        step == .reading || step == .healthDetails || step == .ready ? nil : lastAnswer?.id
    }

    public mutating func toggleGoal(_ goal: TrainingGoal) {
        guard step == .goal else { return }
        var selected = answers.selectedGoals
        if selected.contains(goal) { selected.remove(goal) }
        else { selected.insert(goal) }
        answers.setGoals(selected)
    }

    public mutating func confirmGoals() {
        guard step == .goal, !answers.selectedGoals.isEmpty else { return }
        let titles = answers.orderedGoals.map(\.title)
        answer(titles.joined(separator: ", "),
               reaction: CoachReaction.toGoals(answers.selectedGoals))
        let acknowledgement: String
        if answers.selectedGoals.count >= 3 { acknowledgement = "The whole upgrade. I'll spare you the superhero origin story." }
        else if answers.selectedGoals.contains(.buildMuscle) && answers.selectedGoals.contains(.loseFat) { acknowledgement = "Build muscle and lean out. Steady progress, no crash diets." }
        else if answers.selectedGoals.contains(.getStronger) && answers.selectedGoals.contains(.buildMuscle) { acknowledgement = "Stronger and bigger. Sleeves, consider this your notice." }
        else if answers.selectedGoals.contains(.getStronger) { acknowledgement = "Stronger it is. Let's make the heavy stuff feel lighter." }
        else if answers.selectedGoals.contains(.buildMuscle) { acknowledgement = "Muscle it is. Your T-shirts have been warned." }
        else if answers.selectedGoals.contains(.loseFat) { acknowledgement = "Leaner, without making food your full-time job." }
        else { acknowledgement = "More energy, less running on fumes. I'm in." }
        say("\(acknowledgement) How many days a week do you train?")
        step = .frequency
    }

    public mutating func chooseFrequency(_ frequency: TrainingFrequency) {
        guard step == .frequency else { return }
        answers.frequency = frequency
        answer(frequency == .daily ? frequency.title : "\(frequency.title) days a week",
               reaction: CoachReaction.toFrequency(frequency))
        let acknowledgement: String
        switch frequency {
        case .rarely: acknowledgement = "We'll leave room for life." 
        case .few: acknowledgement = "A few solid days can go a long way."
        case .most: acknowledgement = "That's a regular routine. Recovery gets a seat too."
        case .daily: acknowledgement = "Every day? Let's make sure some are easy ones."
        }
        say("\(acknowledgement) How long have you been training consistently?")
        step = .experience
    }

    public mutating func chooseExperience(_ experience: TrainingExperience) {
        guard step == .experience else { return }
        answers.experience = experience
        answer(experience.title, reaction: nil)
        let acknowledgement: String
        switch experience {
        case .new: acknowledgement = "Fresh start. No catching up to do."
        case .regular: acknowledgement = "You've got a rhythm. We'll build on it."
        case .experienced: acknowledgement = "You know your way around. No beginner reset."
        }
        say("\(acknowledgement) What gets in the way? Pick any that apply.")
        step = .obstacles
    }

    public mutating func toggleObstacle(_ obstacle: Obstacle) {
        guard step == .obstacles else { return }
        if answers.obstacles.contains(obstacle) { answers.obstacles.remove(obstacle) }
        else { answers.obstacles.insert(obstacle) }
    }

    /// `none` is somebody saying nothing is in the way, which is an answer. It clears
    /// anything half-selected, the way the same button does on the injuries question:
    /// the two multi-select questions are the same question shape and behaved
    /// differently, one offering a Skip in the footer and the other a None among the
    /// choices, so the way forward moved between two consecutive screens.
    public mutating func confirmObstacles(none: Bool = false) {
        guard step == .obstacles else { return }
        if none { answers.obstacles = [] }
        let titles = Obstacle.allCases.filter { answers.obstacles.contains($0) }.map(\.title)
        answer(titles.isEmpty ? "Nothing to add" : titles.joined(separator: ", "),
               reaction: nil)
        let acknowledgement: String
        let obstacles = answers.obstacles
        if obstacles.contains(.sleep) && obstacles.contains(.stress) && obstacles.contains(.nutrition) {
            acknowledgement = "Sleep, stress, meals. That's a lot to juggle. We'll keep the plan manageable."
        } else if obstacles.contains(.sleep) && obstacles.contains(.stress) {
            acknowledgement = "Low sleep and stress can pile up. We'll leave room to recover."
        } else if obstacles.contains(.sleep) { acknowledgement = "Running on little sleep is rough. Recovery goes in the plan."
        } else if obstacles.contains(.stress) { acknowledgement = "Let's make training one less thing to stress about."
        } else if obstacles.contains(.nutrition) { acknowledgement = "Meals should fit your life. We'll keep them practical."
        } else if obstacles.contains(.soreness) { acknowledgement = "We'll give recovery some breathing room."
        } else if obstacles.contains(.time) { acknowledgement = "We'll make the time you have count."
        } else if !obstacles.isEmpty { acknowledgement = "We'll keep it repeatable, even when motivation disappears."
        } else { acknowledgement = "A clear runway. Good to know." }
        say("\(acknowledgement) Any physical limits or injuries? Pick any that apply.")
        step = .limitations
    }

    public mutating func toggleLimitation(_ limitation: PhysicalLimitation) {
        guard step == .limitations else { return }
        var selected = answers.limitations ?? []
        if selected.contains(limitation) { selected.remove(limitation) }
        else { selected.insert(limitation) }
        answers.limitations = selected
    }

    public mutating func confirmLimitations(none: Bool = false) {
        guard step == .limitations else { return }
        if none { answers.limitations = [] }
        guard let limits = answers.limitations, none || !limits.isEmpty else { return }
        answer(limits.isEmpty ? "None" : answers.limitationsText ?? "", reaction: nil)
        // Asked of everybody, whatever they said they were here for.
        //
        // It used to be skipped unless the goal was strength or size, on the reasoning
        // that nobody else needed a barbell programme. They get one anyway: the app
        // builds a split for every goal. So somebody here to lose fat was never asked,
        // defaulted to owning nothing, and was handed pull-ups and dips while a pair of
        // dumbbells sat in the room. Meanwhile the coach's own permission screen told
        // him it sends his equipment, which the app had never collected.
        say(limits.isEmpty ? "Good to know. What equipment can you use?" : "I'll work around those limits. What equipment can you use?")
        step = .equipment
    }

    public mutating func chooseEquipment(_ equipment: EquipmentAccess) {
        guard step == .equipment else { return }
        answers.equipment = equipment
        answer(equipment.title)
        let acknowledgement: String
        switch equipment {
        case .fullGym: acknowledgement = "Full gym. Plenty to work with."
        case .dumbbells: acknowledgement = "Dumbbells will do nicely."
        case .bodyweight: acknowledgement = "You bring the equipment. Bodyweight it is."
        }
        // Only asked of somebody training with nothing, because that is the only answer
        // where getting it wrong takes their whole back session away rather than costing
        // them one swap. A pull-up is the best pulling movement available without
        // weights, and whether they own a doorway bar is not something the app can read
        // off anything else. A full gym has bars; a dumbbell owner still has rows.
        if equipment == .bodyweight {
            say("\(acknowledgement) Anything to hang from? A doorway bar counts.")
            step = .pullUpBar
            return
        }
        say("\(acknowledgement) Pounds or kilos?")
        step = .units
    }

    public mutating func choosePullUpBar(has: Bool) {
        guard step == .pullUpBar else { return }
        answers.hasPullUpBar = has
        answer(has ? "Yes" : "No")
        say(has ? "Pull-ups it is. Best thing you can do without weights. Pounds or kilos?"
                : "No problem, we'll work around it. Pounds or kilos?")
        step = .units
    }

    public mutating func chooseUnits(metric: Bool) {
        guard step == .units else { return }
        answers.unitsAreMetric = metric
        answer(metric ? "Kilos" : "Pounds")
        say("Do you wear a watch to bed?")
        step = .watch
    }

    /// Asked once, and never again.
    ///
    /// The answer decides whether the app ever mentions sleep stages and overnight heart
    /// rate to this person. Getting it wrong costs nothing permanent: the record
    /// corrects it, quickly in one direction and slowly in the other. Somebody who buys
    /// a watch six months from now is recognised by their data rather than asked again.
    public mutating func chooseWatch(wearsOne: Bool) {
        guard step == .watch else { return }
        answers.wearsWatchToBed = wearsOne
        answer(wearsOne ? "Yes" : "No")
        say(wearsOne
            ? "Good. That gets me your stages and your overnight heart rate."
            : "No problem. I'll score your sleep on what your phone can see.")
        say("Connect Health so I can use your sleep and activity to guide your training.")
        step = .health
    }

    public mutating func editAnswer(id: Int) {
        guard let lastAnswer, latestEditableAnswerID == id else { return }
        turns.removeSubrange(lastAnswer.count...)
        step = lastAnswer.step
        self.lastAnswer = nil
    }

    public mutating func skipHealth(profile: HealthProfile = HealthProfile(), today: Date = Date()) {
        guard step == .health else { return }
        routeHealthDetails(profile, today: today, skipped: true)
    }

    public mutating func beginReading() {
        guard step == .health else { return }
        step = .reading
    }

    /// `daysRead` is what HealthKit actually returned. It is stated rather than
    /// rounded or dressed up, and when it is zero nothing is claimed at all.
    public mutating func finishReading(hasHealthData: Bool, daysRead: Int = 0,
                                       profile: HealthProfile = HealthProfile(),
                                       today: Date = Date()) {
        guard step == .reading else { return }
        if hasHealthData, daysRead > 0 {
            let nights = daysRead == 1 ? "1 night" : "\(daysRead) nights"
            // The payoff for every question they just answered: their own history,
            // read back to them, with the chart that proves it.
            //
            // Only claimed once there is enough to draw. `BaselineSummary` needs seven
            // readings before it will place anybody in their own range, so below that the
            // reveal under this sentence renders nothing at all, and "that's your normal
            // now" landed over an empty space for every watch bought this week.
            say(daysRead >= BaselineSummary.minimumReadings
                    ? "\(nights), read. That's your normal now, and I'll tell you when it moves."
                    : "\(nights) so far. I need about a week before I can call it your normal.",
                chart: .hrv)
        }
        routeHealthDetails(profile, today: today, skipped: false, hasHealthData: hasHealthData)
    }

    private mutating func routeHealthDetails(_ profile: HealthProfile, today: Date, skipped: Bool, hasHealthData: Bool = false) {
        missingHealthFields = profile.missingFields(on: today)
        if missingHealthFields.isEmpty {
            askForWeightOrFinish()
        } else {
            say(skipped ? "You can connect Health later. Add any missing details here, or skip."
                : "A few details are missing. Add them if you'd like, or skip.")
            step = .healthDetails
        }
    }

    @discardableResult
    public mutating func submitHealthDetails(_ details: HealthProfile, today: Date = Date()) -> Bool {
        guard step == .healthDetails else { return false }
        let allowed = HealthProfile(
            heightCM: missingHealthFields.contains(.height) ? details.heightCM : nil,
            dateOfBirth: missingHealthFields.contains(.dateOfBirth) ? details.dateOfBirth : nil,
            biologicalSex: missingHealthFields.contains(.biologicalSex) ? details.biologicalSex : nil)
        guard allowed.isValid(on: today) else { return false }
        answers.healthDetails = allowed
        answer("Details added")
        askForWeightOrFinish()
        return true
    }

    /// Whether the weight question is worth asking.
    ///
    /// Set by the app once Health has been read. Health knows most people's weight, and
    /// asking for something already on the phone is the kind of question that makes a
    /// setup flow feel like paperwork.
    public var knowsWeight = false

    private mutating func askForWeightOrFinish() {
        guard !knowsWeight else { return askAboutNotifications() }
        say("Last couple of things. Roughly what do you weigh?")
        step = .weight
    }

    public mutating func recordWeight(_ display: String) {
        guard step == .weight else { return }
        answer(display)
        askAboutNotifications()
    }

    public mutating func skipWeight() {
        guard step == .weight else { return }
        answer("Skip")
        askAboutNotifications()
    }

    /// Asked here rather than left in Profile.
    ///
    /// The switch used to live below Baselines, Look and a table of model weights, and
    /// everything the app can start a conversation about was dark for anybody who never
    /// scrolled that far. Asked at the end, where they have seen what the app does and
    /// the promise not to overdo it is something they can check against.
    private mutating func askAboutNotifications() {
        say("Can I message you? Only when I actually know something you don't, "
            + "and you can shut me up whenever.")
        step = .notifications
    }

    public mutating func chooseNotifications(allowed: Bool) {
        guard step == .notifications else { return }
        answer(allowed ? "Go ahead" : "Not now")
        say(allowed ? "Noted. I'll keep it worth reading."
                    : "Fair enough. You'll find me in the app.")
        // A person behind the app, said once, at the moment somebody has just finished
        // setting it up and knows what it does. "text Hao" is a link where it is drawn.
        say("One more thing. If anything's broken or annoying, text Hao. He built me, "
            + "and it goes straight to his phone. It's in Profile too.")
        step = .ready
    }

    public mutating func skipHealthDetails() {
        guard step == .healthDetails else { return }
        answer("Skip for now")
        askForWeightOrFinish()
    }

    private mutating func answer(_ text: String, reaction: CoachReaction? = nil) {
        lastAnswer = LastAnswer(id: nextID, step: step, count: turns.count)
        turns.append(Turn(id: nextID, isUser: true, text: text, reaction: reaction))
        nextID += 1
    }

    private mutating func say(_ text: String, chart: MetricKind? = nil) {
        turns.append(Turn(id: nextID, isUser: false, text: text, reaction: nil, chart: chart))
        nextID += 1
    }
}

extension CoachContextBuilder {
    /// A declined or empty Health read still permits a conversation, without inventing a score.
    public static func withoutHealth(today: Date, goal: String?) -> CoachContext {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return CoachContext(today: formatter.string(from: today), state: "unknown",
                            composite: 0, confidence: "none", daysOfHistory: 0, gate: nil,
                            metrics: [], checkIn: nil, acwr: nil, recentDays: [], program: [],
                            proposedAdjustments: [],
                            uncertainty: ["No Health data is available. There is no readiness score or baseline; the zero composite is a placeholder, not a measurement."],
                            goal: goal, limitations: nil)
    }
}
