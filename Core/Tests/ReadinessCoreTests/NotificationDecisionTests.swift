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

    @Test("the same news the next day goes out again: novelty does not gate the verdict")
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
            tonightsNeed: SleepNeed(hours: 8.9, baseline: 8.0,
                                    strainAdjustment: 0.7, napCredit: 0,
                                    learnedShare: 1),
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
        // `record` is threaded through the loop: reassigned from whatever each call
        // actually returns, rather than left untouched. A version that discarded each
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
        let need = SleepNeed(hours: 8.9, baseline: 8.0,
                             strainAdjustment: 0.7, napCredit: 0,
                             learnedShare: 1)
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
            tonightsNeed: SleepNeed(hours: 8.9, baseline: 8.0,
                                    strainAdjustment: 0.7, napCredit: 0,
                                    learnedShare: 1),
            usualBedtime: bedtime))
        #expect(outcome?.moment == .morningVerdict)
    }

    // MARK: - Review findings

    /// A gate score, with the magnitude fixed low enough that `MorningVerdict.sentence`
    /// never fires on its own, so tests below can prove what blocks the *gate itself*
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
    // low magnitude so a deleted guard is caught by the gate firing again, not by a
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

    // IMPORTANT 2: mirrors `repeatsAcrossDays`: the guard must not block forever.
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
    // through real `next(_:)` calls rather than a hand-set record: deleting all
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

    // IMPORTANT 3: the bedtime target's once-per-day guard, mirroring `onePerDay`.
    @Test("the bedtime target goes out once a day, however often the app refreshes")
    func bedtimeOnePerDay() {
        let bedtime = morning.addingTimeInterval(14 * 3600)
        var record = NotificationRecord()
        record.lastBedtimeTarget = bedtime.addingTimeInterval(-80 * 60)
        let outcome = NotificationDecision.next(input(
            now: bedtime.addingTimeInterval(-20 * 60),
            tonightsNeed: SleepNeed(hours: 8.9, baseline: 8.0,
                                    strainAdjustment: 0.7, napCredit: 0,
                                    learnedShare: 1),
            usualBedtime: bedtime,
            record: record))
        #expect(outcome == nil)
    }

    // IMPORTANT 3: mirrors `repeatsAcrossDays`: an unusual night the following evening
    // still gets its own message.
    @Test("the bedtime target fires again the next evening if it's unusual again")
    func bedtimeRepeatsNextDay() {
        let bedtime = morning.addingTimeInterval(14 * 3600)
        var record = NotificationRecord()
        record.lastBedtimeTarget = bedtime.addingTimeInterval(-30 * 60)
        let nextBedtime = bedtime.addingTimeInterval(24 * 3600)
        let outcome = NotificationDecision.next(input(
            now: nextBedtime.addingTimeInterval(-30 * 60),
            tonightsNeed: SleepNeed(hours: 8.9, baseline: 8.0,
                                    strainAdjustment: 0.7, napCredit: 0,
                                    learnedShare: 1),
            usualBedtime: nextBedtime,
            record: record))
        #expect(outcome?.moment == .bedtimeTarget)
    }

    // IMPORTANT 3: pins `record.lastBedtimeTarget = input.now` itself, round-tripping
    // through real `next(_:)` calls. Without it the guard above can never see a same-day
    // match, so the engine would re-fire on every refresh inside the 90-minute window:
    // draining all three coins in an hour and a half.
    @Test("the bedtime target's own send is what blocks its next refresh")
    func bedtimeWriteIsWhatBlocksIt() {
        let bedtime = morning.addingTimeInterval(14 * 3600)
        let need = SleepNeed(hours: 8.9, baseline: 8.0,
                             strainAdjustment: 0.7, napCredit: 0,
                             learnedShare: 1)
        let first = NotificationDecision.next(input(
            now: bedtime.addingTimeInterval(-80 * 60),
            tonightsNeed: need, usualBedtime: bedtime))
        #expect(first?.moment == .bedtimeTarget)

        let second = NotificationDecision.next(input(
            now: bedtime.addingTimeInterval(-20 * 60),
            tonightsNeed: need, usualBedtime: bedtime,
            record: first!.record))
        #expect(second == nil)
    }

    // MINOR 9: `!insight.isEmpty` was unguarded by any test.
    @Test("an empty insight is not news")
    func emptyInsightIsSilent() {
        #expect(NotificationDecision.next(input(insight: "")) == nil)
    }

    // IMPORTANT 4: the gate's body used to be `ReadinessGate.elevatedWristTemperature
    // .explanation`: an in-app paragraph of about 245 characters that exceeds
    // lock-screen truncation and never states the instruction this notification IS.
    @Test("the gate's body is a short instruction, not the in-app paragraph")
    func gateBodyIsLockScreenSafe() {
        let outcome = NotificationDecision.next(
            input(recovery: score(.recovery, value: 8, magnitude: -30,
                                  gate: .elevatedWristTemperature)))
        #expect(outcome?.body == "🌡️ Your temperature was up overnight. Don't train hard today.")
        #expect((outcome?.body.count ?? .max) < 110)
    }

    // IMPORTANT 6, ruling from the controller: the spec's "`.unavailable` coverage
    // produces no notification of any kind" was written about today's data driving
    // today's messages (morning verdict, illness gate, bedtime target). An insight is
    // derived from session history, not today's scores, so it stays true, and worth
    // sending, on a day the watch was not worn. No guard was added; this test pins
    // that the exemption is deliberate rather than an oversight.
    @Test("an insight still speaks when today's scores are unavailable")
    func insightSpeaksEvenWhenTodayIsUnavailable() {
        let unavailable = SignalScore(kind: .recovery, value: nil, band: nil,
                                      contributors: [], coverage: .unavailable,
                                      modelVersion: "test")
        let unavailableSleep = SignalScore(kind: .sleep, value: nil, band: nil,
                                           contributors: [], coverage: .unavailable,
                                           modelVersion: "test")
        let outcome = NotificationDecision.next(input(
            recovery: unavailable, sleep: unavailableSleep, insight: "Something new."))
        #expect(outcome?.moment == .newInsight)
    }
}

/// Booking the bedtime target ahead, so it arrives whether or not the app happens to be
/// open in the ninety minutes before bed. Deciding it only at those moments meant it
/// almost never arrived at all.
@Suite("Planning the bedtime target ahead")
struct BedtimePlanTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let morning = Date(timeIntervalSince1970: 1_800_000_000)
    private var bedtime: Date { morning.addingTimeInterval(14 * 3600) }
    private var fireAt: Date { bedtime.addingTimeInterval(-BedtimeTarget.leadMinutes * 60) }
    private let unusual = SleepNeed(hours: 8.9, baseline: 8.0, strainAdjustment: 0.7,
                                    napCredit: 0, learnedShare: 1)
    private let ordinary = SleepNeed(hours: 8.1, baseline: 8.0, strainAdjustment: 0.1,
                                     napCredit: 0, learnedShare: 1)

    private func score(_ kind: SignalKind) -> SignalScore {
        SignalScore(kind: kind, value: 72, band: nil, contributors: [], coverage: .full,
                    neutral: 50, gate: nil, modelVersion: "test")
    }

    private func input(now: Date? = nil, need: SleepNeed? = nil, usualBedtime: Date? = nil,
                       debt: Double = 0,
                       record: NotificationRecord = NotificationRecord()) -> NotificationDecision.Input {
        NotificationDecision.Input(
            now: now ?? morning, recovery: score(.recovery), sleep: score(.sleep),
            recentSleepScores: [], tonightsNeed: need, sleepDebtHours: debt,
            usualBedtime: usualBedtime, record: record, calendar: calendar)
    }

    private func coinsLeft(_ record: NotificationRecord, at now: Date) -> Int {
        var state = record.budget
        var left = 0
        while NotificationBudget.consume(state, now: now).allowed {
            state = NotificationBudget.consume(state, now: now).state
            left += 1
        }
        return left
    }

    @Test("an unusual night is booked for an hour before the usual bedtime, in the morning")
    func booksAhead() {
        let plan = NotificationDecision.bedtimeBooking(input(need: unusual, usualBedtime: bedtime)).plan
        #expect(plan?.fireAt == fireAt)
        #expect(plan?.body == BedtimeTarget.sentence(need: unusual))
        #expect(plan?.record.lastBedtimeTarget == fireAt)
        #expect(coinsLeft(plan!.record, at: morning) == NotificationBudget.capacity - 1)
    }

    @Test("an ordinary night withdraws any booking")
    func ordinaryNight() {
        #expect(NotificationDecision.bedtimeBooking(input(need: ordinary, usualBedtime: bedtime)) == .withdraw)
    }

    // A phone woken in the background while locked cannot read Health. Not knowing is
    // not the same as the night being ordinary, and must not cancel a booking.
    @Test("missing inputs leave any booking alone")
    func missingInputs() {
        #expect(NotificationDecision.bedtimeBooking(input(need: unusual)) == .leave)
        #expect(NotificationDecision.bedtimeBooking(input(usualBedtime: bedtime)) == .leave)
        #expect(NotificationDecision.bedtimeBooking(input()) == .leave)
    }

    @Test("a time already past is not booked, and is left to the window")
    func pastIsNotBooked() {
        let late = input(now: bedtime.addingTimeInterval(-30 * 60), need: unusual,
                         usualBedtime: bedtime)
        #expect(NotificationDecision.bedtimeBooking(late) == .leave)
        #expect(NotificationDecision.bedtimeBooking(input(now: fireAt, need: unusual,
                                                       usualBedtime: bedtime)) == .leave)
    }

    // The app plans on every refresh. Each one must replace the booking, not pay again.
    @Test("booking the same night again refreshes the words and costs nothing")
    func rebookingIsFree() {
        let first = NotificationDecision.bedtimeBooking(input(need: unusual, usualBedtime: bedtime)).plan!
        var record = first.record
        for hour in 1...8 {
            let again = NotificationDecision.bedtimeBooking(input(
                now: morning.addingTimeInterval(Double(hour) * 3600), need: unusual,
                usualBedtime: bedtime, debt: 3, record: record)).plan
            #expect(again?.fireAt == fireAt)
            record = again?.record ?? record
        }
        #expect(coinsLeft(record, at: morning) == coinsLeft(first.record, at: morning))
    }

    // The window path and the booking share one record, so one night is one message.
    @Test("once booked, the window stays quiet that evening")
    func bookingSilencesTheWindow() {
        let plan = NotificationDecision.bedtimeBooking(input(need: unusual, usualBedtime: bedtime)).plan!
        let inWindow = NotificationDecision.next(input(
            now: bedtime.addingTimeInterval(-20 * 60), need: unusual,
            usualBedtime: bedtime, record: plan.record))
        #expect(inWindow?.moment != .bedtimeTarget)
    }

    @Test("once the window has already spoken, nothing more is booked that night")
    func windowSilencesTheBooking() {
        let spoke = NotificationDecision.next(input(
            now: bedtime.addingTimeInterval(-85 * 60), need: unusual, usualBedtime: bedtime))!
        #expect(spoke.moment == .bedtimeTarget)
        let plan = NotificationDecision.bedtimeBooking(input(
            now: bedtime.addingTimeInterval(-80 * 60), need: unusual,
            usualBedtime: bedtime, record: spoke.record))
        #expect(plan == .leave)
    }

    @Test("an empty allowance books nothing")
    func emptyAllowance() {
        var record = NotificationRecord()
        record.budget = NotificationBudget.State(tokens: 0, updated: morning)
        #expect(NotificationDecision.bedtimeBooking(input(need: unusual, usualBedtime: bedtime,
                                                       record: record)) == .leave)
    }

    @Test("the next unusual night is booked again")
    func nextNight() {
        let first = NotificationDecision.bedtimeBooking(input(need: unusual, usualBedtime: bedtime)).plan!
        let tomorrow = NotificationDecision.bedtimeBooking(input(
            now: morning.addingTimeInterval(24 * 3600), need: unusual,
            usualBedtime: bedtime.addingTimeInterval(24 * 3600), record: first.record)).plan
        #expect(tomorrow?.fireAt == fireAt.addingTimeInterval(24 * 3600))
    }

    // A night that flaps, unusual then ordinary then unusual, is paid for once.
    @Test("a withdrawn and rebooked night costs one coin")
    func flappingNight() {
        let first = NotificationDecision.bedtimeBooking(input(need: unusual, usualBedtime: bedtime)).plan!
        #expect(NotificationDecision.bedtimeBooking(input(
            now: morning.addingTimeInterval(3600), need: ordinary, usualBedtime: bedtime,
            record: first.record)) == .withdraw)
        let again = NotificationDecision.bedtimeBooking(input(
            now: morning.addingTimeInterval(7200), need: unusual, usualBedtime: bedtime,
            record: first.record)).plan
        #expect(again?.fireAt == fireAt)
        #expect(coinsLeft(again!.record, at: morning) == coinsLeft(first.record, at: morning))
    }

    // Usual bedtime moves during the day: the booking follows it rather than keeping
    // the old time or sending twice.
    @Test("a later usual bedtime moves the booking")
    func bedtimeMoves() {
        let first = NotificationDecision.bedtimeBooking(input(need: unusual, usualBedtime: bedtime)).plan!
        let later = bedtime.addingTimeInterval(40 * 60)
        let moved = NotificationDecision.bedtimeBooking(input(
            now: morning.addingTimeInterval(3600), need: unusual, usualBedtime: later,
            record: first.record)).plan
        #expect(moved?.fireAt == later.addingTimeInterval(-BedtimeTarget.leadMinutes * 60))
    }

    // A bedtime after midnight books the evening before, and that evening's window stays
    // quiet because the booking already speaks for it.
    @Test("a bedtime after midnight is booked the evening before, once")
    func pastMidnight() {
        let lateBed = morning.addingTimeInterval(16 * 3600 + 30 * 60)
        let plan = NotificationDecision.bedtimeBooking(input(need: unusual, usualBedtime: lateBed)).plan!
        #expect(plan.fireAt == lateBed.addingTimeInterval(-3600))
        let inWindow = NotificationDecision.next(input(
            now: lateBed.addingTimeInterval(-20 * 60), need: unusual,
            usualBedtime: lateBed, record: plan.record))
        #expect(inWindow?.moment != .bedtimeTarget)
    }

    // The words are for a lock screen: they must stand alone and fit.
    @Test("the booked words stand alone on a lock screen")
    func lockScreenWords() {
        let plan = NotificationDecision.bedtimeBooking(input(need: unusual, usualBedtime: bedtime,
                                                             debt: 4)).plan!
        #expect(plan.body.count < 110)
        #expect(!plan.body.contains("\u{2014}"))
        #expect(plan.body.hasSuffix("."))
    }

    // The app books first and then asks `next` with what it just booked. If the copy
    // dropped anything, the window would decide on a different night than was booked.
    @Test("carrying a new record keeps everything else about the moment")
    func withRecordKeepsTheRest() {
        let original = input(now: fireAt.addingTimeInterval(-600), need: unusual,
                             usualBedtime: bedtime, debt: 2)
        var record = NotificationRecord()
        record.lastBedtimeTarget = fireAt
        let carried = original.with(record: record)
        #expect(carried.record == record)
        #expect(carried.now == original.now)
        #expect(carried.tonightsNeed == original.tonightsNeed)
        #expect(carried.usualBedtime == original.usualBedtime)
        #expect(carried.sleepDebtHours == original.sleepDebtHours)
        #expect(carried.calendar == original.calendar)
    }
}
