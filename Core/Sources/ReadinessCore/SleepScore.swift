import Foundation

/// How much sleep tonight actually had to be, rather than a number somebody picked.
///
/// A fixed eight-hour target says the same thing to somebody six hours in the hole after
/// a hard week as it does to somebody who has slept nine every night on holiday. Whoop's
/// model is the one worth copying here: a baseline the body has, plus what you still owe,
/// plus what today cost you, minus what you already took back in a nap.
/// How much sleep last night had to be.
///
/// Deliberately NOT debt-adjusted, which is a reversal. Folding a running balance into a
/// nightly score meant two identical nights scored differently for a reason nobody could
/// act on that night — and measured over sixty nights it made a constant 7h30 sleeper
/// change band on 44% of them, because the debt cap parked almost everybody's need on
/// exactly the same number and left them a fraction of a point from a boundary. It also
/// put a hard ceiling on anyone habitually under 7h26m: green was unreachable at any
/// quality.
///
/// Debt is a stock and a night is a flow. The stock lives in `SleepDebt` now, where it
/// can be shown as a balance with a direction, and it feeds recovery — which is the
/// question it actually answers.
public struct SleepNeed: Sendable, Equatable {
    public let hours: Double
    public let baseline: Double
    public let strainAdjustment: Double
    public let napCredit: Double

    /// The nightly requirement before anything else applies.
    public static let baselineHours = 8.0

    /// Strain below this costs nothing extra. Half the scale.
    public static let strainThreshold = 50.0
    /// The extra asked for at the very top of the strain scale.
    public static let strainExtraHours = 0.75

    public static let maximumNapCreditHours = 1.0

    public static let minimumHours = 6.0
    public static let maximumHours = 11.0

    /// Yesterday's load is a property of the night that had to repair it, not a running
    /// balance, so it stays. It is capped at three quarters of an hour, which is small
    /// enough that it cannot park anybody on a band edge.
    public static func of(strain: Double? = nil, napHours: Double? = nil) -> SleepNeed {
        let adjustment = strain.map {
            Swift.max(0, ($0 - strainThreshold) / (StrainScore.scaleMax - strainThreshold))
                * strainExtraHours
        } ?? 0
        let nap = Swift.min(Swift.max(0, napHours ?? 0), maximumNapCreditHours)
        return SleepNeed(hours: clamp(baselineHours + adjustment - nap),
                         baseline: baselineHours,
                         strainAdjustment: adjustment, napCredit: nap)
    }

    private static func clamp(_ hours: Double) -> Double {
        Swift.min(maximumHours, Swift.max(minimumHours, hours))
    }
}

/// What you are down on sleep, as a running balance.
///
/// A stock, not a score: the interesting number is which way it moved. It is shown on its
/// own card with that direction, and it feeds recovery, where "how far behind am I" is
/// the question being asked.
public struct SleepDebt: Sendable, Equatable {
    /// Outstanding hours, never negative — sleeping extra pays the hole down and then
    /// stops. Being twelve hours "ahead" is not a thing anybody can spend.
    public let hours: Double
    /// Signed change from the night before. Negative is progress.
    public let change: Double
    public let nights: Int

    /// How far back it looks. Longer than the old seven-night window, because a balance
    /// that forgets last Tuesday is not a balance.
    public static let window = 14

    /// A real ceiling rather than a scoring convenience. Past this the number stops
    /// being information and starts being an accusation.
    public static let maximumHours = 12.0

    /// `nights` is hours slept, oldest first, ending with last night.
    public static func of(nights: [Double]) -> SleepDebt {
        let usable = nights.filter { $0.isFinite && $0 >= 0 }.suffix(window)
        let balance = accumulate(Array(usable))
        let previous = accumulate(Array(usable.dropLast()))
        return SleepDebt(hours: balance, change: balance - previous, nights: usable.count)
    }

    private static func accumulate(_ nights: [Double]) -> Double {
        var debt = 0.0
        for slept in nights {
            debt = Swift.min(maximumHours, Swift.max(0, debt + (SleepNeed.baselineHours - slept)))
        }
        return debt
    }
}

public struct SleepInput: Sendable {
    public let breakdown: SleepBreakdown?
    public let durationHours: Double?
    /// Trailing nights, for judging tonight's structure against this sleeper's own.
    public let history: [SleepBreakdown]
    /// Yesterday's strain, 0...100.
    public let strain: Double?
    public let napHours: Double?
    public let sleepingHeartRate: Double?
    /// The waking, non-active average, which is what the dip is measured against.
    public let daytimeHeartRate: Double?
    public let calendar: Calendar

    public init(breakdown: SleepBreakdown?, durationHours: Double?,
                history: [SleepBreakdown] = [],
                strain: Double? = nil, napHours: Double? = nil,
                sleepingHeartRate: Double? = nil, daytimeHeartRate: Double? = nil,
                calendar: Calendar = .current) {
        self.breakdown = breakdown
        self.durationHours = durationHours
        self.history = history
        self.strain = strain
        self.napHours = napHours
        self.sleepingHeartRate = sleepingHeartRate
        self.daytimeHeartRate = daytimeHeartRate
        self.calendar = calendar
    }
}

/// What last night was worth, as a share of what it needed to be.
///
/// Duration against need is the headline, the way Whoop does it. Structure adjusts it
/// within a narrow band, the way AutoSleep's quality does — but every structural
/// component is scored against this sleeper's own distribution rather than an invented
/// ideal. That constraint is inherited from docs/briefs/signal-scores.md and it is the
/// reason deep and REM can be scored at all: the app never claims to know how much deep
/// sleep a person should get, only whether they got less of it than they usually do.
///
/// See docs/superpowers/specs/2026-09-19-signal-scores-design.md.
public enum SleepScore {

    public static let modelVersion = "sleep-v1.0.0"

    /// Structure can move the score by this much and no more. Duration has to dominate:
    /// a beautifully built five hours is still five hours, and a score that let good
    /// architecture rescue a short night would be telling people the wrong thing.
    public static let qualityFloor = 0.85

    /// Where a full, well-built night lands, and what the breakdown counts down from.
    public static let perfect = 100.0

    /// The share of the waking heart rate that a strong overnight dip represents.
    /// AutoSleep calls 15% and above the athlete band; this is the top of the scale
    /// rather than a claim about anybody's health.
    public static let fullDip = 0.15

    /// Where the dip stops costing anything. AutoSleep calls 10-15% the normal band, and
    /// scoring against the top of it meant a perfectly ordinary 10% dip lost points every
    /// night of a person's life.
    public static let normalDip = 0.12

    /// What an unmeasured component is assumed to have been. A shade under a good night,
    /// so an unmeasured night lands below a measured good one and above a measured bad one.
    static let typicalComponentLevel = 0.9

    /// Shares live in 0...1, so their baseline band needs a floor of its own.
    static let shareDeviationFloor = 0.01
    static let hoursDeviationFloor = 0.1

    /// Below this, being awake is stirring rather than an awakening. The stage ring
    /// already hid it; the tile beside it was still printing it, so three parts of the
    /// screen disagreed about whether the person woke up.
    public static let minimumReportedAwakeHours = 0.25

    public static let durationContributorID = "duration"
    public static let dipContributorID = "dip"

    public static func of(_ input: SleepInput) -> SignalScore {
        let hours = input.durationHours ?? input.breakdown?.recordedSleepHours
        guard let hours, hours.isFinite, hours > 0 else {
            return SignalScore(kind: .sleep, value: nil, band: nil, contributors: [],
                               coverage: .unavailable, missing: ["Sleep"],
                               neutral: perfect, modelVersion: modelVersion)
        }

        let need = SleepNeed.of(strain: input.strain, napHours: input.napHours)
        let performance = Swift.min(1, hours / need.hours)

        // A component nobody measured counts as an ordinary one, never as a perfect one.
        //
        // Dropping the missing ones from the average meant a phone with no sensors
        // scored 100 on a night an Apple Watch could only score 96 on, because every
        // structural component it could not see was treated as flawless. Measuring less
        // must not score higher.
        let components = quality(input)
        let fraction = components
            .map { $0.fraction ?? typicalComponentLevel }
            .reduce(0, +) / Double(components.count)
        let qualityFactor = qualityFloor + (1 - qualityFloor) * fraction
        let value = perfect * performance * qualityFactor

        // The night is decomposed the way it is lost: first the hours that were not
        // there, then what the remaining hours failed to do. Every row is a subtraction
        // from a full night, so they sum to the distance below one hundred.
        let durationLoss = perfect * (1 - performance)
        let qualityLoss = perfect * performance * (1 - qualityFactor)
        // Only measured components can be blamed for the loss. The stand-in charge for
        // the ones nobody recorded is real, but attributing it to a measured row put a
        // 99% night's headline on its single good component.
        let shortfalls = components.map { component -> Double in
            guard let fraction = component.fraction else { return 0 }
            return 1 - fraction
        }
        let totalShortfall = shortfalls.reduce(0, +)

        var rows = [ScoreContributor(
            id: durationContributorID,
            title: "Time asleep",
            value: hours,
            unit: "h",
            comparison: need.hours,
            comparisonLabel: "your need",
            state: performance >= 0.95 ? .optimal : (performance >= 0.8 ? .fine : .payAttention),
            level: performance,
            symbol: "bed.double.fill",
            magnitude: -durationLoss,
            explanation: needExplanation(need))]

        for (component, shortfall) in zip(components, shortfalls) {
            guard let fraction = component.fraction else { continue }
            let share = totalShortfall > 0 ? shortfall / totalShortfall : 0
            rows.append(ScoreContributor(
                id: component.id,
                title: component.title,
                value: component.value,
                unit: component.unit,
                comparison: component.comparison,
                comparisonLabel: component.comparisonLabel,
                state: fraction >= 0.7 ? .optimal : (fraction >= 0.4 ? .fine : .payAttention),
                level: fraction,
                symbol: component.symbol,
                magnitude: -qualityLoss * share,
                explanation: component.explanation,
                note: component.note))
        }

        let missing = components.filter { $0.fraction == nil }.map(\.missingLabel)
        // Most of the night unmeasured means the baselines are still being built, which
        // is a different thing to say than "not counted today".
        let measured = components.count - missing.count
        let coverage: ScoreCoverage = missing.isEmpty
            ? .full : (measured <= 2 ? .buildingBaseline : .partial)
        return SignalScore(
            kind: .sleep,
            value: value,
            band: .sleep(percent: value),
            contributors: rows.sorted { abs($0.magnitude) > abs($1.magnitude) },
            coverage: coverage,
            missing: missing,
            neutral: perfect,
            modelVersion: modelVersion)
    }

    // MARK: - Quality components

    struct Component {
        let id: String
        let title: String
        /// 0...1, or nil when it could not be measured. Nil drops it from the average
        /// rather than scoring it as a failure.
        let fraction: Double?
        let value: Double?
        let unit: String
        let comparison: Double?
        let comparisonLabel: String?
        let explanation: String
        let missingLabel: String
        let symbol: String
        /// What this row says in one sentence. A night's parts need saying in their own
        /// terms — "0.5 h against the 1 h a night this long usually gives you" is a
        /// different sentence from "below your normal", and only the engine knows which
        /// of the two it means.
        var note: String? = nil
    }

    static func quality(_ input: SleepInput) -> [Component] {
        let night = input.breakdown
        let asleep = night?.asleepHours ?? 0

        /// Whether a night's stages can be trusted.
        ///
        /// Two ways they cannot. A night recorded as plain "asleep" has no stages at all,
        /// and that is not the same as a night with no deep sleep in it — the app used to
        /// tell somebody whose watch was on the charger that they got zero hours of REM
        /// and rank it as the reason their night was poor. And a phone and a watch both
        /// recording can report more staged hours than the night contained, which
        /// `HealthSource` already refuses to split but the scorer did not: one probe drew
        /// a ring reading "Deep 7.0 h" on a seven-hour night, arcs summing to 129% of it.
        func isStaged(_ night: SleepBreakdown) -> Bool {
            let stages = night.deepHours + night.remHours + night.coreHours
            return stages > 0 && stages <= night.asleepHours + 0.01
        }
        let staged = night.map(isStaged) ?? false

        func share(_ keyPath: KeyPath<SleepBreakdown, Double>) -> Double? {
            guard let night, asleep > 0, staged else { return nil }
            return night[keyPath: keyPath] / asleep
        }

        /// Where tonight's value sits in this sleeper's own distribution, as 0...1.
        /// Higher is better, so an inverted quantity is flipped before it is read.
        /// Recentred so that being typical is not a penalty.
        ///
        /// A plain Φ gives your own median 0.5, so an utterly ordinary night lost points
        /// on every self-relative component and the leading reason for the loss was a
        /// value identical to the person's own average. Doubling and clamping puts the
        /// median at 1.0 and charges only the downside, which is the only side anybody
        /// can act on.
        func relative(_ current: Double?, _ historic: [Double],
                      floor: Double, higherIsBetter: Bool = true) -> Double? {
            guard let current,
                  let summary = BaselineSummary.of(historic, minimumDeviation: floor)
            else { return nil }
            let z = (current - summary.mean) / summary.deviation
            return Swift.min(1, 2 * Percentile.fromZ(higherIsBetter ? z : -z))
        }

        // Only nights whose stages are trustworthy may set the baseline the current
        // night is judged against.
        let stagedHistory = input.history.filter(isStaged)

        let historicShares = { (keyPath: KeyPath<SleepBreakdown, Double>) -> [Double] in
            stagedHistory.compactMap { past in
                past.asleepHours > 0 ? past[keyPath: keyPath] / past.asleepHours : nil
            }
        }

        let schedule = regularity(breakdown: night, history: input.history,
                                  calendar: input.calendar)

        let dip: Double? = {
            guard let sleeping = input.sleepingHeartRate, let daytime = input.daytimeHeartRate,
                  sleeping.isFinite, daytime.isFinite, daytime > 0 else { return nil }
            return (daytime - sleeping) / daytime
        }()

        // What a night this long usually gives this sleeper, so a stage row compares
        // like with like. A short night has less deep sleep in it by arithmetic, and
        // saying so against a fixed hour count would blame them for the clock.
        func usualHours(_ keyPath: KeyPath<SleepBreakdown, Double>) -> Double? {
            guard asleep > 0,
                  let summary = BaselineSummary.of(historicShares(keyPath),
                                                   minimumDeviation: shareDeviationFloor)
            else { return nil }
            return summary.mean * asleep
        }

        func hours(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(0...1))) + " h"
        }

        let continuityFraction = night?.recordedContinuity
        let deepUsual = usualHours(\.deepHours)
        let remUsual = usualHours(\.remHours)
        let awakeUsual = BaselineSummary.of(stagedHistory.map(\.awakeHours),
                                            minimumDeviation: hoursDeviationFloor)?.mean

        return [
            Component(
                id: "continuity", title: "Solid sleep",
                fraction: continuityFraction,
                value: continuityFraction.map { $0 * 100 }, unit: "%",
                comparison: 100, comparisonLabel: nil,
                explanation: "How much of the night was actually spent asleep rather "
                           + "than awake or merely in bed. Eight broken hours are not "
                           + "eight hours, and this is the part that notices.",
                missingLabel: "Sleep stages, so continuity could not be read",
                symbol: "moon.zzz.fill",
                note: continuityFraction.map {
                    $0 >= 0.95 ? "You barely stirred."
                        : ($0 >= 0.85 ? "Broken up a little, but mostly solid."
                                      : "You spent a fair bit of the night not asleep.")
                }),
            Component(
                id: "schedule", title: "Bedtime",
                fraction: schedule.fraction,
                value: schedule.medianMinutes, unit: "min",
                comparison: nil, comparisonLabel: nil,
                explanation: "How far last night's bedtime was from the one you normally "
                           + "keep. Going to bed at the same time is one of the few sleep "
                           + "levers that costs nothing to pull.",
                missingLabel: "Seven nights of bedtimes",
                symbol: "clock.fill",
                note: schedule.medianMinutes.map {
                    $0 < 20 ? "Right on your usual bedtime."
                        : "You went to bed about \(Int($0.rounded())) minutes off your usual time."
                }),
            Component(
                id: "deep", title: "Deep sleep",
                fraction: relative(share(\.deepHours), historicShares(\.deepHours),
                                   floor: shareDeviationFloor),
                value: night.map { $0.deepHours }, unit: "h",
                comparison: deepUsual, comparisonLabel: "your usual",
                explanation: "The share of the night spent in deep sleep, measured "
                           + "against your own nights rather than an ideal. There is no "
                           + "agreed correct amount, and anybody who tells you there is "
                           + "made it up — but a night well below your own usual is "
                           + "worth knowing about.",
                missingLabel: "Seven nights of stage data for deep sleep",
                symbol: "moon.fill",
                note: deepUsual.map { "A night this long usually gives you \(hours($0))." }),
            Component(
                id: "rem", title: "REM sleep",
                fraction: relative(share(\.remHours), historicShares(\.remHours),
                                   floor: shareDeviationFloor),
                value: night.map { $0.remHours }, unit: "h",
                comparison: remUsual, comparisonLabel: "your usual",
                explanation: "The share of the night spent in REM, against your own "
                           + "nights. It is the stage most easily cut short by alcohol "
                           + "and by waking early.",
                missingLabel: "Seven nights of stage data for REM",
                symbol: "eye.fill",
                note: remUsual.map { "A night this long usually gives you \(hours($0))." }),
            Component(
                id: "awake", title: "Time awake",
                fraction: relative(staged ? night?.awakeHours : nil,
                                   stagedHistory.map(\.awakeHours),
                                   floor: hoursDeviationFloor, higherIsBetter: false),
                value: night.map { $0.awakeHours < minimumReportedAwakeHours ? 0 : $0.awakeHours },
                unit: "h",
                comparison: awakeUsual, comparisonLabel: "your usual",
                explanation: "Time spent awake between falling asleep and getting up, "
                           + "against how much you normally lose. Everybody surfaces "
                           + "during the night; the question is whether last night was "
                           + "worse than yours usually are.",
                missingLabel: "Seven nights of stage data for awakenings",
                symbol: "sun.horizon.fill",
                note: awakeUsual.map { "You normally lose about \(hours($0)) to being awake." }),
            Component(
                id: dipContributorID, title: "Overnight heart rate drop",
                fraction: dip.map { Swift.min(1, Swift.max(0, $0 / normalDip)) },
                value: dip.map { $0 * 100 }, unit: "%",
                comparison: normalDip * 100, comparisonLabel: nil,
                explanation: "How far your heart rate fell overnight against your "
                           + "waking average. A large drop is the clearest sign the "
                           + "night was restorative rather than merely long.",
                missingLabel: "Overnight and daytime heart rate",
                symbol: "arrow.down.heart.fill",
                note: dip.map {
                    $0 >= fullDip ? "A big drop — your body settled properly."
                        : ($0 >= 0.10 ? "A normal drop."
                        : ($0 >= 0.05 ? "A smaller drop than usual."
                                      : "Your heart rate stayed high for a night's rest."))
                }),
        ]
    }

    private static func needExplanation(_ need: SleepNeed) -> String {
        var parts = ["Your need last night was \(format(need.hours)) hours: "
                     + "\(format(need.baseline)) as a baseline"]
        if need.strainAdjustment > 0 {
            parts.append("plus \(format(need.strainAdjustment)) for how hard yesterday was")
        }
        if need.napCredit > 0 {
            parts.append("less \(format(need.napCredit)) you already took in a nap")
        }
        return parts.joined(separator: ", ") + "."
    }

    private static func format(_ hours: Double) -> String {
        hours.formatted(.number.precision(.fractionLength(0...1)))
    }

    // MARK: - Schedule regularity

    /// Unchanged in substance from the engine this replaces: the median clock distance
    /// between last night's bed and wake times and the ones before it, mapped from zero
    /// to two hours. Now returns the median itself as well, so the row can show it.
    static func regularity(breakdown: SleepBreakdown?, history: [SleepBreakdown],
                           calendar: Calendar) -> (fraction: Double?, medianMinutes: Double?) {
        guard let current = breakdown, let start = current.primarySleepStart,
              let end = current.primarySleepEnd, end > start,
              let cutoff = calendar.date(byAdding: .day, value: -28,
                                         to: calendar.startOfDay(for: end)) else {
            return (nil, nil)
        }
        let today = calendar.startOfDay(for: end)
        var prior: [Date: SleepBreakdown] = [:]
        for night in history {
            guard let sleepStart = night.primarySleepStart, let sleepEnd = night.primarySleepEnd,
                  sleepEnd > sleepStart else { continue }
            let day = calendar.startOfDay(for: sleepEnd)
            guard day < today, day >= cutoff else { continue }
            prior[day] = night
        }
        guard prior.count >= 7 else { return (nil, nil) }
        // Bed time only. Using wake time as well meant any change in duration moved one
        // of the two, so the ten-hour recovery night the need model had just asked for
        // came back as the night's worst offender for irregularity.
        _ = end
        let differences = prior.values.compactMap { night -> Double? in
            guard let otherStart = night.primarySleepStart else { return nil }
            return clockDistance(start, otherStart, calendar: calendar)
        }.sorted()
        guard !differences.isEmpty else { return (nil, nil) }
        let middle = differences.count / 2
        let median = differences.count.isMultiple(of: 2)
            ? (differences[middle - 1] + differences[middle]) / 2 : differences[middle]
        return (max(0, 1 - median / 120), median)
    }

    private static func clockDistance(_ first: Date, _ second: Date, calendar: Calendar) -> Double {
        func minutes(_ date: Date) -> Double {
            let components = calendar.dateComponents([.hour, .minute], from: date)
            return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        }
        let difference = abs(minutes(first) - minutes(second))
        return min(difference, 1440 - difference)
    }
}
