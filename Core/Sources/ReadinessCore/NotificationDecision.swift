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
        /// Nil when there are not enough nights to know when this person goes to bed.
        public let usualBedtime: Date?
        public let insight: String?
        public let record: NotificationRecord
        public let calendar: Calendar

        public init(now: Date, recovery: SignalScore, sleep: SignalScore,
                    recentSleepScores: [Double] = [], tonightsNeed: SleepNeed? = nil,
                    usualBedtime: Date? = nil, insight: String? = nil,
                    record: NotificationRecord = NotificationRecord(),
                    calendar: Calendar = .current) {
            self.now = now
            self.recovery = recovery
            self.sleep = sleep
            self.recentSleepScores = recentSleepScores
            self.tonightsNeed = tonightsNeed
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
        /// coin for a message the user never saw — so the app must persist this only
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
        "Your temperature was up overnight. Don't train hard today."

    private static func illnessGate(_ input: Input) -> Outcome? {
        guard input.recovery.gate == .elevatedWristTemperature,
              !input.record.alreadySentToday(.illnessGate, now: input.now,
                                             calendar: input.calendar)
        else { return nil }
        var record = input.record
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
        var record = input.record
        record.lastMorningVerdict = input.now
        return Outcome(moment: .morningVerdict, body: body, record: record)
    }

    private static func bedtimeTarget(_ input: Input) -> Outcome? {
        guard let need = input.tonightsNeed, let bedtime = input.usualBedtime,
              BedtimeTarget.isDue(now: input.now, usualBedtime: bedtime),
              !input.record.alreadySentToday(.bedtimeTarget, now: input.now,
                                             calendar: input.calendar),
              let body = BedtimeTarget.sentence(need: need)
        else { return nil }
        // The coin is spent last, so a moment that was going to be skipped anyway costs
        // nothing and the allowance survives for the day that needs it.
        guard var record = spend(input.record, now: input.now) else { return nil }
        record.lastBedtimeTarget = input.now
        return Outcome(moment: .bedtimeTarget, body: body, record: record)
    }

    private static func newInsight(_ input: Input) -> Outcome? {
        guard let insight = input.insight, !insight.isEmpty,
              insight != input.record.lastInsight
        else { return nil }
        guard var record = spend(input.record, now: input.now) else { return nil }
        record.lastInsight = insight
        return Outcome(moment: .newInsight, body: insight, record: record)
    }

    /// Nil when the bucket is empty, which is the whole of the refusal.
    private static func spend(_ record: NotificationRecord, now: Date) -> NotificationRecord? {
        let decision = NotificationBudget.consume(record.budget, now: now)
        guard decision.allowed else { return nil }
        var spent = record
        spent.budget = decision.state
        return spent
    }
}
