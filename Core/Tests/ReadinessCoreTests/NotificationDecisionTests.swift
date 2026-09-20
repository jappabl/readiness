import Testing
import Foundation
@testable import ReadinessCore

/// The whole rule, end to end: which moment wins, what silences it, and what a message
/// costs.
@Suite("Deciding whether Jett speaks")
struct NotificationDecisionTests {

    /// Pinned to UTC, for the same reason as `NotificationRecordTests`: `morningThenBedtime`
    /// puts thirteen and a half hours between two instants and asserts they are the same
    /// day, which is false east of about UTC+3 under the system calendar.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let morning = Date(timeIntervalSince1970: 1_800_000_000)

    private func score(_ kind: SignalKind, value: Double, magnitude: Double,
                       gate: ReadinessGate? = nil) -> SignalScore {
        SignalScore(
            kind: kind, value: value, band: nil,
            contributors: [ScoreContributor(
                id: "hrv", title: "Heart rate variability", value: 42, unit: "ms",
                comparison: 58, comparisonLabel: "your normal", state: .payAttention,
                magnitude: magnitude, explanation: "")],
            coverage: .full, neutral: 50, gate: gate, modelVersion: "test")
    }

    private func input(
        now: Date? = nil,
        recovery: SignalScore? = nil,
        sleep: SignalScore? = nil,
        // Above the default sleep fixture (80), so an ordinary morning is not silently
        // a personal best and the silence tests below test what they claim to.
        recentSleepScores: [Double] = Array(repeating: 94.0, count: 21),
        tonightsNeed: SleepNeed? = nil,
        usualBedtime: Date? = nil,
        insight: String? = nil,
        record: NotificationRecord = NotificationRecord()
    ) -> NotificationDecision.Input {
        NotificationDecision.Input(
            now: now ?? morning,
            recovery: recovery ?? score(.recovery, value: 72, magnitude: 0.4),
            sleep: sleep ?? score(.sleep, value: 80, magnitude: 0.4),
            recentSleepScores: recentSleepScores,
            tonightsNeed: tonightsNeed,
            usualBedtime: usualBedtime,
            insight: insight,
            record: record,
            calendar: calendar)
    }

    @Test("an ordinary morning with nothing else going on says nothing")
    func quietMorning() {
        #expect(NotificationDecision.next(input()) == nil)
    }

    @Test("a bad morning produces the verdict")
    func badMorning() {
        let outcome = NotificationDecision.next(
            input(recovery: score(.recovery, value: 41, magnitude: -11)))
        #expect(outcome?.moment == .morningVerdict)
    }

    @Test("the illness gate outranks the morning verdict")
    func gateWins() {
        let outcome = NotificationDecision.next(
            input(recovery: score(.recovery, value: 8, magnitude: -30,
                                  gate: .elevatedWristTemperature)))
        #expect(outcome?.moment == .illnessGate)
    }

    @Test("a load spike is not the illness gate")
    func loadSpikeIsNotIllness() {
        let outcome = NotificationDecision.next(
            input(recovery: score(.recovery, value: 60, magnitude: -11,
                                  gate: .acuteLoadSpike)))
        #expect(outcome?.moment == .morningVerdict)
    }

    @Test("the verdict goes out once a day, however often the app refreshes")
    func onePerDay() {
        var record = NotificationRecord()
        record.lastMorningVerdict = morning
        let outcome = NotificationDecision.next(input(
            now: morning.addingTimeInterval(4 * 3600),
            recovery: score(.recovery, value: 41, magnitude: -11),
            record: record))
        #expect(outcome == nil)
    }

    @Test("the same news the next day goes out again — novelty does not gate the verdict")
    func repeatsAcrossDays() {
        var record = NotificationRecord()
        record.lastMorningVerdict = morning
        let outcome = NotificationDecision.next(input(
            now: morning.addingTimeInterval(24 * 3600),
            recovery: score(.recovery, value: 41, magnitude: -11),
            record: record))
        #expect(outcome?.moment == .morningVerdict)
    }

    @Test("an empty bucket cannot silence the verdict or the gate")
    func exemptMomentsIgnoreTheBucket() {
        var record = NotificationRecord()
        record.budget = NotificationBudget.State(tokens: 0, updated: morning)
        #expect(NotificationDecision.next(input(
            recovery: score(.recovery, value: 41, magnitude: -11),
            record: record))?.moment == .morningVerdict)
        #expect(NotificationDecision.next(input(
            recovery: score(.recovery, value: 8, magnitude: -30,
                            gate: .elevatedWristTemperature),
            record: record))?.moment == .illnessGate)
    }

    @Test("an empty bucket does silence an insight")
    func bucketSilencesInsight() {
        var record = NotificationRecord()
        record.budget = NotificationBudget.State(tokens: 0, updated: morning)
        #expect(NotificationDecision.next(input(insight: "Something true.",
                                                record: record)) == nil)
    }

    @Test("an insight that has already been said is not news")
    func insightNovelty() {
        var record = NotificationRecord()
        record.lastInsight = "Something true."
        #expect(NotificationDecision.next(input(insight: "Something true.",
                                                record: record)) == nil)
    }

    @Test("a new insight speaks and is remembered")
    func newInsightSpeaks() {
        let outcome = NotificationDecision.next(input(insight: "Something new."))
        #expect(outcome?.moment == .newInsight)
        #expect(outcome?.record.lastInsight == "Something new.")
    }

    @Test("a bedtime target speaks in its window and spends a coin")
    func bedtimeSpeaks() {
        let bedtime = morning.addingTimeInterval(14 * 3600)
        let now = bedtime.addingTimeInterval(-30 * 60)
        let outcome = NotificationDecision.next(input(
            now: now,
            tonightsNeed: SleepNeed(hours: 8.9, baseline: 8.0, debt: 0.2,
                                    strainAdjustment: 0.7, napCredit: 0),
            usualBedtime: bedtime))
        #expect(outcome?.moment == .bedtimeTarget)

        // A full jar minus this message leaves exactly capacity - 1 more in the instant,
        // which is what "it spent a coin" means.
        var left = 0
        var state = outcome!.record.budget
        while NotificationBudget.consume(state, now: now).allowed {
            state = NotificationBudget.consume(state, now: now).state
            left += 1
        }
        #expect(left == NotificationBudget.capacity - 1)
    }

    @Test("a quiet day leaves the whole allowance for the day that needs it")
    func skippedMomentsAreFree() {
        // A hundred quiet decisions in a row, then one real insight. If a skipped
        // moment ever cost a coin, the jar would be empty long before the news arrived.
        //
        // `record` is threaded through the loop — reassigned from whatever each call
        // actually returns — rather than left untouched. A version that discarded each
        // call's result would call `next` on the same untouched fresh record every
        // time, which stays nil regardless of what the decision does internally, and
        // would pass even if a skipped moment quietly spent a coin.
        var record = NotificationRecord()
        for _ in 0..<100 {
            let outcome = NotificationDecision.next(input(record: record))
            #expect(outcome == nil)
            record = outcome?.record ?? record
        }
        let outcome = NotificationDecision.next(input(insight: "Something new.",
                                                      record: record))
        #expect(outcome?.moment == .newInsight)
    }

    @Test("a morning outranks a bedtime target, and the bedtime still comes that evening")
    func morningThenBedtime() {
        let bedtime = morning.addingTimeInterval(14 * 3600)
        let need = SleepNeed(hours: 8.9, baseline: 8.0, debt: 0.2,
                             strainAdjustment: 0.7, napCredit: 0)
        let first = NotificationDecision.next(input(
            recovery: score(.recovery, value: 41, magnitude: -11),
            tonightsNeed: need, usualBedtime: bedtime))
        #expect(first?.moment == .morningVerdict)

        let second = NotificationDecision.next(input(
            now: bedtime.addingTimeInterval(-30 * 60),
            recovery: score(.recovery, value: 41, magnitude: -11),
            tonightsNeed: need, usualBedtime: bedtime,
            record: first!.record))
        #expect(second?.moment == .bedtimeTarget)
    }

    /// `morningThenBedtime` never actually tests priority: its first call has a bedtime
    /// that is not due yet, and its second call has a morning already sent, so
    /// `bedtimeTarget` and `morningVerdict` respectively were never going to fire there
    /// regardless of which is tried first. This is the one call where both are eligible
    /// at once, so only priority order decides.
    @Test("when both are eligible in the same call, the morning verdict wins on priority alone")
    func morningOutranksBedtimeWhenBothEligible() {
        let bedtime = morning.addingTimeInterval(14 * 3600)
        let now = bedtime.addingTimeInterval(-30 * 60)
        let outcome = NotificationDecision.next(input(
            now: now,
            recovery: score(.recovery, value: 41, magnitude: -11),
            tonightsNeed: SleepNeed(hours: 8.9, baseline: 8.0, debt: 0.2,
                                    strainAdjustment: 0.7, napCredit: 0),
            usualBedtime: bedtime))
        #expect(outcome?.moment == .morningVerdict)
    }

    // MARK: - Review findings

    /// A gate score, with the magnitude fixed low enough that `MorningVerdict.sentence`
    /// never fires on its own — so tests below can prove what blocks the *gate itself*
    /// without a fallback to the verdict muddying the result.
    private func gateScore(magnitude: Double = -3) -> SignalScore {
        score(.recovery, value: 60, magnitude: magnitude, gate: .elevatedWristTemperature)
    }

    // CRITICAL 1: `illnessGate` stamped `lastIllnessGate` but not `lastMorningVerdict`.
    // HealthKit background delivery runs hourly, so the very next refresh that same
    // morning found the gate blocked by its own day guard and fell through to
    // `morningVerdict`, which fired as a strictly weaker restatement of the same fact.
    @Test("a gate morning does not also fire the verdict on the next refresh")
    func gateAlsoStampsTheVerdict() {
        let recovery = score(.recovery, value: 8, magnitude: -30,
                             gate: .elevatedWristTemperature)
        let first = NotificationDecision.next(input(recovery: recovery))
        #expect(first?.moment == .illnessGate)

        let second = NotificationDecision.next(input(
            now: morning.addingTimeInterval(3600),
            recovery: recovery,
            record: first!.record))
        #expect(second == nil)
    }

    // IMPORTANT 2: the illness gate's once-per-day guard, mirroring `onePerDay`. Uses a
    // low magnitude so a deleted guard is caught by the gate firing again — not by a
    // `morningVerdict` fallback, which would also fire and mask the real signal.
    @Test("the gate goes out once a day, however often the app refreshes")
    func gateOnePerDay() {
        var record = NotificationRecord()
        record.lastIllnessGate = morning
        let outcome = NotificationDecision.next(input(
            now: morning.addingTimeInterval(4 * 3600),
            recovery: gateScore(),
            record: record))
        #expect(outcome == nil)
    }

    // IMPORTANT 2: mirrors `repeatsAcrossDays` — the guard must not block forever.
    @Test("the gate fires again the next day if the illness persists")
    func gateRepeatsAcrossDays() {
        var record = NotificationRecord()
        record.lastIllnessGate = morning
        let outcome = NotificationDecision.next(input(
            now: morning.addingTimeInterval(24 * 3600),
            recovery: gateScore(),
            record: record))
        #expect(outcome?.moment == .illnessGate)
    }

    // IMPORTANT 2: pins `record.lastIllnessGate = input.now` itself, round-tripping
    // through real `next(_:)` calls rather than a hand-set record — deleting all
    // review-noted lines here, that write is the one still isolated: the gate's own
    // guard is exercised by `gateOnePerDay` above, and the low magnitude keeps
    // `morningVerdict` silent so only the gate's repeat behavior is on trial.
    @Test("the gate's own send is what blocks its next refresh")
    func gateWriteIsWhatBlocksIt() {
        let first = NotificationDecision.next(input(recovery: gateScore()))
        #expect(first?.moment == .illnessGate)

        let second = NotificationDecision.next(input(
            now: morning.addingTimeInterval(4 * 3600),
            recovery: gateScore(),
            record: first!.record))
        #expect(second == nil)
    }

    // IMPORTANT 4: the gate's body used to be `ReadinessGate.elevatedWristTemperature
    // .explanation` — an in-app paragraph of about 245 characters that exceeds
    // lock-screen truncation and never states the instruction this notification IS.
    @Test("the gate's body is a short instruction, not the in-app paragraph")
    func gateBodyIsLockScreenSafe() {
        let outcome = NotificationDecision.next(
            input(recovery: score(.recovery, value: 8, magnitude: -30,
                                  gate: .elevatedWristTemperature)))
        #expect(outcome?.body == "Your temperature was up overnight. Don't train hard today.")
        #expect((outcome?.body.count ?? .max) < 110)
    }
}
