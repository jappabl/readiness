import Testing
import Foundation
@testable import ReadinessCore

/// Em dashes read as machine-written, so the product does not use them. A comma, a full
/// stop, or a new sentence does the same job without the tell.
@Suite("Punctuation the product does not use")
struct PunctuationTests {

    private func check(_ strings: [String], _ source: String) {
        for text in strings {
            #expect(!text.contains("—"), "em dash in \(source): \"\(text)\"")
            #expect(!text.contains("--"), "double hyphen standing in for one in \(source)")
        }
    }

    @Test("no metric copy uses one")
    func metrics() {
        check(MetricKind.allCases.flatMap { [$0.displayName, $0.unit, $0.explanation] },
              "MetricKind")
    }

    @Test("no goal copy uses one")
    func goals() {
        check(TrainingGoal.allCases.flatMap { [$0.title, $0.promise] }, "TrainingGoal")
    }

    @Test("no onboarding copy uses one")
    func onboarding() {
        check(TrainingFrequency.allCases.flatMap { [$0.title, $0.detail] }, "TrainingFrequency")
        check(Obstacle.allCases.map(\.title), "Obstacle")
    }

    // MARK: - Generated copy
    //
    // The enums above are a fixed list; a grep over their cases catches everything they
    // can ever say. Notification copy is not: `MorningVerdict.sentence`, `BedtimeTarget
    // .sentence` and `NotificationDecision.next` build a sentence from a real score at
    // runtime, so an em dash regressing into one of their building blocks (`SignalScore
    // .summary`, in fact, once did) never shows up in a fixed-string sweep. These tests
    // build real scores and check what actually comes out.

    /// A score with one contributor that moved it by `magnitude` points, the same shape
    /// `MorningVerdictTests` and `NotificationDecisionTests` build by hand.
    private func score(_ kind: SignalKind, value: Double, magnitude: Double,
                       title: String = "Heart rate variability",
                       gate: ReadinessGate? = nil) -> SignalScore {
        SignalScore(
            kind: kind, value: value, band: nil,
            contributors: [ScoreContributor(
                id: "hrv", title: title, value: 42, unit: "ms",
                comparison: 58, comparisonLabel: "your normal", state: .payAttention,
                magnitude: magnitude, explanation: "")],
            coverage: .full, neutral: 50, gate: gate, modelVersion: "test")
    }

    private func flatScore(_ kind: SignalKind, value: Double) -> SignalScore {
        score(kind, value: value, magnitude: 0.4)
    }

    /// Above the 80/88 an ordinary night uses and below the 96 an exceptional one does,
    /// same as `MorningVerdictTests`.
    private let ordinaryHistory = Array(repeating: 94.0, count: 21)

    @Test("a full contributor still summarises without one")
    func signalSummary() {
        check([score(.recovery, value: 55, magnitude: -14).summary,
               score(.sleep, value: 40, magnitude: -14, title: "Deep sleep").summary],
              "SignalScore.summary")
    }

    @Test("no morning verdict sentence uses one")
    func morningVerdictSentences() {
        let sentences = [
            // The signal moved further down through recovery.
            MorningVerdict.sentence(
                recovery: score(.recovery, value: 44, magnitude: -9),
                sleep: flatScore(.sleep, value: 80),
                recentSleepScores: ordinaryHistory),
            // The signal moved further down through sleep.
            MorningVerdict.sentence(
                recovery: flatScore(.recovery, value: 71),
                sleep: score(.sleep, value: 58, magnitude: -11),
                recentSleepScores: ordinaryHistory),
            // A genuine best night.
            MorningVerdict.sentence(
                recovery: score(.recovery, value: 82, magnitude: 8),
                sleep: score(.sleep, value: 96, magnitude: 6),
                recentSleepScores: ordinaryHistory),
        ]
        check(sentences.compactMap { $0 }, "MorningVerdict.sentence")
    }

    @Test("no bedtime target sentence uses one")
    func bedtimeTargetSentences() {
        let sentences = [
            // A hard day drove tonight's need.
            BedtimeTarget.sentence(need: SleepNeed(
                hours: 8.75, baseline: SleepNeed.baselineHours,
                debt: 0.1, strainAdjustment: 0.7, napCredit: 0)),
            // Accumulated debt drove it instead.
            BedtimeTarget.sentence(need: SleepNeed(
                hours: 8.8, baseline: SleepNeed.baselineHours,
                debt: 1.4, strainAdjustment: 0.05, napCredit: 0)),
        ]
        check(sentences.compactMap { $0 }, "BedtimeTarget.sentence")
    }

    @Test("no notification body uses one")
    func notificationBodies() {
        check(allGeneratedBodies(), "NotificationDecision.next")
    }

    // MARK: - Emoji policy
    //
    // Exactly one emoji per notification body, leading, as a category marker: never
    // mid-sentence, never standing in for a word, never more than one. In-app copy stays
    // emoji-free; this only governs what actually leaves through a notification.

    /// Whether `character` renders as emoji, rather than merely being flagged `isEmoji`
    /// in Unicode's own data, which is also true of plain digits, `#` and `*` because
    /// they can lead a keycap sequence. Checking that naively would flag "Recovery 41."
    /// as carrying a hidden emoji in every digit. A glyph that actually renders as one
    /// either sits above the code point where digits and plain symbols end, or is built
    /// from more than one scalar, such as a variation selector or a skin-tone modifier.
    private func isEmojiGlyph(_ character: Character) -> Bool {
        guard let first = character.unicodeScalars.first else { return false }
        return first.properties.isEmoji
            && (first.value > 0x238C || character.unicodeScalars.count > 1)
    }

    /// At most one emoji, and if present, it is the first character.
    private func hasAtMostOneLeadingEmoji(_ text: String) -> Bool {
        let emojiPositions = text.indices.filter { isEmojiGlyph(text[$0]) }
        switch emojiPositions.count {
        case 0: return true
        case 1: return emojiPositions[0] == text.startIndex
        default: return false
        }
    }

    @Test("every generatable notification body has at most one emoji, leading")
    func emojiPolicy() {
        for body in allGeneratedBodies() {
            #expect(hasAtMostOneLeadingEmoji(body),
                    "emoji missing, duplicated, or not leading: \"\(body)\"")
        }
    }

    /// Every notification body the engine can actually produce, one per marker: the
    /// battery, the sleeping face, the sparkle, the thermometer, the crescent moon and
    /// the bulb. Strain's flame is not reachable here: `MorningVerdict.sentence` only
    /// ever compares recovery against sleep, so `marker(for:)`'s strain case is
    /// unreachable through the public surface this sweep pins.
    private func allGeneratedBodies() -> [String] {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar
        }()

        func input(now: Date, recovery: SignalScore, sleep: SignalScore,
                   tonightsNeed: SleepNeed? = nil, usualBedtime: Date? = nil,
                   insight: String? = nil) -> NotificationDecision.Input {
            NotificationDecision.Input(
                now: now, recovery: recovery, sleep: sleep,
                recentSleepScores: ordinaryHistory, tonightsNeed: tonightsNeed,
                usualBedtime: usualBedtime, insight: insight, calendar: calendar)
        }

        let ordinaryRecovery = flatScore(.recovery, value: 72)
        let ordinarySleep = flatScore(.sleep, value: 80)

        // The gate fires regardless of the contributor: the thermometer.
        let illnessGate = NotificationDecision.next(input(
            now: now,
            recovery: score(.recovery, value: 8, magnitude: -30,
                           gate: .elevatedWristTemperature),
            sleep: ordinarySleep))

        // Recovery moved it, with no gate: the battery.
        let morningVerdict = NotificationDecision.next(input(
            now: now,
            recovery: score(.recovery, value: 41, magnitude: -11),
            sleep: ordinarySleep))

        // Sleep moved it instead: the sleeping face.
        let sleepLed = NotificationDecision.next(input(
            now: now, recovery: ordinaryRecovery,
            sleep: score(.sleep, value: 58, magnitude: -11)))

        // A genuine best night: the sparkle.
        let bestNight = NotificationDecision.next(input(
            now: now,
            recovery: score(.recovery, value: 82, magnitude: 8),
            sleep: score(.sleep, value: 96, magnitude: 6)))

        // The crescent moon.
        let bedtime = now.addingTimeInterval(14 * 3600)
        let bedtimeTarget = NotificationDecision.next(input(
            now: bedtime.addingTimeInterval(-30 * 60),
            recovery: ordinaryRecovery, sleep: ordinarySleep,
            tonightsNeed: SleepNeed(hours: 8.9, baseline: 8.0, debt: 0.2,
                                    strainAdjustment: 0.7, napCredit: 0),
            usualBedtime: bedtime))

        // The bulb.
        let newInsight = NotificationDecision.next(input(
            now: now, recovery: ordinaryRecovery, sleep: ordinarySleep,
            insight: "Your training volume has been about 18% higher."))

        return [illnessGate, morningVerdict, sleepLed, bestNight, bedtimeTarget, newInsight]
            .compactMap { $0?.body }
    }
}
