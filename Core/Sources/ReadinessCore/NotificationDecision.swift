import Foundation

/// Whether Coach Jett says anything right now, and what.
///
/// The whole product rule in one pure function: the app interrupts when it knows
/// something the user does not, that changes what they do today. Everything this returns
/// is decided here and merely delivered by the app layer, so every decision in
/// docs/superpowers/specs/2026-09-19-notifications-design.md is provable by `swift test`.
public enum NotificationDecision {

    public struct Input: Sendable {
        public let now: Date
        public let recovery: SignalScore
        public let sleep: SignalScore
        /// Sleep scores for the trailing nights, oldest first, excluding today.
        public let recentSleepScores: [Double]
        /// Nil when the app cannot work out what tonight needs.
        public let tonightsNeed: SleepNeed?
        /// Hours currently owed. Separate from the need since sleep debt became a
        /// decaying balance of its own rather than a term folded into tonight's target.
        public let sleepDebtHours: Double
        /// Nil when there are not enough nights to know when this person goes to bed.
        public let usualBedtime: Date?
        public let insight: String?
        public let record: NotificationRecord
        public let calendar: Calendar

        public init(now: Date, recovery: SignalScore, sleep: SignalScore,
                    recentSleepScores: [Double] = [], tonightsNeed: SleepNeed? = nil,
                    sleepDebtHours: Double = 0,
                    usualBedtime: Date? = nil, insight: String? = nil,
                    record: NotificationRecord = NotificationRecord(),
                    calendar: Calendar = .current) {
            self.now = now
            self.recovery = recovery
            self.sleep = sleep
            self.recentSleepScores = recentSleepScores
            self.tonightsNeed = tonightsNeed
            self.sleepDebtHours = sleepDebtHours
            self.usualBedtime = usualBedtime
            self.insight = insight
            self.record = record
            self.calendar = calendar
        }
    }

    public struct Outcome: Equatable, Sendable {
        public let moment: NotificationMoment
        public let body: String
        /// The record to persist, with this message written into it and any coin spent.
        ///
        /// This is the record as of the DECISION, not the delivery: the day is stamped
        /// and the coin is spent here, before the app has shown anything. If the
        /// delivery layer persisted this unconditionally, a denied permission or a
        /// failed `UNUserNotificationCenter.add` would silently burn the day and the
        /// coin for a message the user never saw, so the app must persist this only
        /// after the notification is confirmed delivered.
        public let record: NotificationRecord
    }

    /// Highest priority first. The gate leads because it is the one thing the app may
    /// know before the user does, and training hard into an illness is the concrete harm
    /// the app exists to prevent.
    public static func next(_ input: Input) -> Outcome? {
        if let outcome = illnessGate(input) { return outcome }
        if let outcome = morningVerdict(input) { return outcome }
        if let outcome = bedtimeTarget(input) { return outcome }
        return newInsight(input)
    }

    /// The gate's own words, written for a lock screen rather than borrowed from
    /// `ReadinessGate.elevatedWristTemperature.explanation`. That string runs to about
    /// 245 characters, was written for a scrollable in-app row, references "here" (which
    /// does not exist on a lock screen), and never states the instruction this
    /// notification IS: don't train hard today.
    private static let illnessGateBody =
        "🌡️ Your temperature was up overnight. Don't train hard today."

    private static func illnessGate(_ input: Input) -> Outcome? {
        guard input.recovery.gate == .elevatedWristTemperature,
              !input.record.alreadySentToday(.illnessGate, now: input.now,
                                             calendar: input.calendar)
        else { return nil }
        guard var record = spend(input.record, moment: .illnessGate, now: input.now)
        else { return nil }
        record.lastIllnessGate = input.now
        // The gate IS this morning's verdict. Without this the verdict fires on the very
        // next refresh, restating the same fact in weaker words.
        record.lastMorningVerdict = input.now
        return Outcome(moment: .illnessGate, body: Self.illnessGateBody, record: record)
    }

    private static func morningVerdict(_ input: Input) -> Outcome? {
        guard !input.record.alreadySentToday(.morningVerdict, now: input.now,
                                             calendar: input.calendar),
              let body = MorningVerdict.sentence(recovery: input.recovery,
                                                 sleep: input.sleep,
                                                 recentSleepScores: input.recentSleepScores)
        else { return nil }
        guard var record = spend(input.record, moment: .morningVerdict, now: input.now)
        else { return nil }
        record.lastMorningVerdict = input.now
        return Outcome(moment: .morningVerdict, body: body, record: record)
    }

    private static func bedtimeTarget(_ input: Input) -> Outcome? {
        guard let need = input.tonightsNeed, let bedtime = input.usualBedtime,
              BedtimeTarget.isDue(now: input.now, usualBedtime: bedtime),
              !input.record.alreadySentToday(.bedtimeTarget, now: input.now,
                                             calendar: input.calendar),
              let body = BedtimeTarget.sentence(need: need,
                                                debtHours: input.sleepDebtHours)
        else { return nil }
        // The coin is spent last, so a moment that was going to be skipped anyway costs
        // nothing and the allowance survives for the day that needs it.
        guard var record = spend(input.record, moment: .bedtimeTarget, now: input.now)
        else { return nil }
        record.lastBedtimeTarget = input.now
        return Outcome(moment: .bedtimeTarget, body: body, record: record)
    }

    private static func newInsight(_ input: Input) -> Outcome? {
        guard let insight = input.insight, !insight.isEmpty,
              insight != input.record.lastInsight
        else { return nil }
        guard var record = spend(input.record, moment: .newInsight, now: input.now)
        else { return nil }
        record.lastInsight = insight
        // The bulb marks the category. The finding is already a whole sentence.
        return Outcome(moment: .newInsight, body: "💡 \(insight)", record: record)
    }

    /// Nil when the bucket is empty for a moment that draws from it.
    ///
    /// `NotificationMoment.spendsBudget` is the single source of truth for which moments
    /// cost a token. This used to be stated a second time here, structurally, by which
    /// of the four helpers simply never called `spend` at all, so the two could drift
    /// silently if a helper's wiring changed without touching the enum. Every helper
    /// calls this now, and a moment for which `spendsBudget` is false passes through
    /// unchanged and can never be refused, regardless of the bucket's state.
    private static func spend(_ record: NotificationRecord, moment: NotificationMoment,
                              now: Date) -> NotificationRecord? {
        guard moment.spendsBudget else { return record }
        let decision = NotificationBudget.consume(record.budget, now: now)
        guard decision.allowed else { return nil }
        var spent = record
        spent.budget = decision.state
        return spent
    }
}

/// When it is acceptable for Jett to speak at all, before anything is decided about
/// whether he has something worth saying.
///
/// Two different things could wake this app up, and they carry different evidence. One
/// is somebody putting the app down, which says nothing about whether they want to hear
/// from it in ten minutes. The other is their watch handing over a finished night, which
/// happens because they woke up and it synced: that is not a guess about whether they
/// are awake, it is a record of it.
///
/// The clock used to govern both. Anybody whose night ended between eleven at night and
/// five in the morning had the one message the app exists to send dropped on the floor,
/// and a night nurse never got a morning verdict at all.
public enum SpeakingWindow {

    public enum Trigger: Sendable, Equatable {
        /// They closed the app. No evidence either way, so the clock decides.
        case appClosed
        /// Their watch just handed over a finished night, which only happens because
        /// they woke and it synced.
        case nightSynced
    }

    /// Nobody is woken by this app. The window exists for the case where all we have is
    /// the time of day.
    public static let quietFrom = 23
    public static let quietUntil = 5

    /// Long enough to be sure somebody is up and not simply turning over.
    ///
    /// A watch syncs the moment a night ends, which can be a few minutes before anybody
    /// has their eyes properly open. Twelve minutes is the difference between arriving
    /// with somebody's morning and arriving in the middle of it.
    public static let wakeSettlingDelay: TimeInterval = 12 * 60

    public static func allows(_ trigger: Trigger, at now: Date,
                              calendar: Calendar = .current) -> Bool {
        switch trigger {
        // Evidence beats the clock. They are demonstrably awake, whatever the hour.
        case .nightSynced: return true
        case .appClosed:
            let hour = calendar.component(.hour, from: now)
            return hour >= quietUntil && hour < quietFrom
        }
    }

    /// How long to wait before speaking, once it has been decided that speaking is
    /// allowed.
    public static func delay(after trigger: Trigger) -> TimeInterval {
        switch trigger {
        case .nightSynced: return wakeSettlingDelay
        case .appClosed: return 0
        }
    }
}
