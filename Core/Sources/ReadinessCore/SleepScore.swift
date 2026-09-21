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
/// act on that night, and measured over sixty nights it made a constant 7h30 sleeper
/// change band on 44% of them, because the debt cap parked almost everybody's need on
/// exactly the same number and left them a fraction of a point from a boundary. It also
/// put a hard ceiling on anyone habitually under 7h26m: green was unreachable at any
/// quality.
///
/// Debt is a stock and a night is a flow. The stock lives in `SleepDebt` now, where it
/// can be shown as a balance with a direction, and it feeds recovery, which is the
/// question it actually answers.
/// A need estimated from somebody's own nights, and how much of it really was theirs.
public struct LearnedNeed: Sendable, Equatable {
    public let hours: Double
    /// 0 when the answer is entirely the population figure, 1 when entirely their own.
    public let confidence: Double
}

public struct SleepNeed: Sendable, Equatable {
    public let hours: Double
    public let baseline: Double
    public let strainAdjustment: Double
    public let napCredit: Double
    /// How much of `baseline` was learned from this sleeper rather than assumed.
    ///
    /// `baseline(from:)` returns a blend of their own estimate and the population figure,
    /// and the sentence explaining the need used to credit the whole of it to "what your
    /// own longest nights take". For somebody 28 nights into a 7.05 h habit that named
    /// 7.9 hours as theirs when only 7.05 of it was, and every user with a non-8.0
    /// estimate passes through about a fortnight of it on the way up.
    public let learnedShare: Double

    /// The nightly requirement when nothing better is known.
    ///
    /// A population average, and the only number in the app applied to a person rather
    /// than learned from them, every other thing measured here is scored against the
    /// user's own history. `baseline(from:)` replaces it as soon as there is enough to
    /// learn from.
    public static let baselineHours = 8.0

    /// Nights needed before a personal need can be estimated at all.
    public static let learningNights = 14

    /// Where in the person's own distribution their need sits.
    ///
    /// Not the median: that is the trap. A chronically under-slept person's median is
    /// their deprivation, and scoring them against it would hand them 100 for sleeping
    /// six hours and call the job done. The upper part of the distribution is what they
    /// take when nothing stops them, which is the closest thing to unrestricted sleep
    /// that can be observed without asking.
    ///
    /// But not the far tail either, and that is a real objection: a need at the 80th
    /// percentile means four nights in five fall short by construction, which reads as
    /// "you always need more sleep" to somebody who is sleeping perfectly well.
    ///
    /// 0.75 is the lowest value that still works, and the reason is the shape of an
    /// ordinary week. Five restricted weekdays and two free weekends put the
    /// unrestricted nights in the top two sevenths (above the 71st percentile) so
    /// anything lower collapses into the weekday cluster and learns the deprivation
    /// instead. Measured on that pattern: 0.50 gives a need of 6.5 h, 0.65 gives 7.2 h,
    /// and 0.75 gives 8.8 h, which is the weekend. The cost to somebody under no
    /// restriction at all is about four points on a typical night.
    public static let needPercentile = 0.75

    public static let learnedFloorHours = 7.0
    public static let learnedCeilingHours = 9.5

    /// What this person's own nights say they need.
    ///
    /// Falls back to the population figure in the one case the estimate cannot be
    /// trusted: when even their long nights are below the floor, there is no evidence of
    /// an unrestricted night anywhere in the record, so the number would be a measure of
    /// how constrained they are rather than of what they need. Leaving them on the
    /// population average is the harsher answer and the honest one: the alternative
    /// quietly lowers the bar for exactly the person who is furthest from clearing it.
    public static func baseline(from nights: [Double]) -> LearnedNeed {
        let usable = nights.filter { $0.isFinite && $0 > 0 }.sorted()
        guard usable.count >= learningNights else {
            return LearnedNeed(hours: baselineHours, confidence: 0)
        }

        // A band rather than a single index. On a weekday/weekend record the
        // distribution is two clusters with nothing between them, so a point estimate
        // sits on whichever night happens to land at the index, and one missing night
        // moved the need by a full hour, which moved an ordinary night ten points.
        let span = usable.indices.filter {
            let q = Double($0) / Double(Swift.max(1, usable.count - 1))
            return q >= needPercentile - needBand && q <= needPercentile + needBand
        }
        let estimate = span.isEmpty
            ? usable[usable.count - 1]
            : span.reduce(0.0) { $0 + usable[$1] } / Double(span.count)

        // Ramped into the fallback rather than switched. At a hard threshold six minutes
        // of habitual sleep bought twelve points and a band, and a person whose estimate
        // hovered near it crossed back and forth invisibly.
        let trust = Swift.min(1, Swift.max(0, (estimate - learnedFloorHours) / learnedRampHours))
        // And the night count is a threshold too. Switching from the population figure
        // to the learned one in a single step moved an unchanged sleeper up to eleven
        // points overnight, and a gappy record could cross back and forth over it.
        let settled = Swift.min(1, Double(usable.count - learningNights)
                                / Double(learningNights))
        let confidence = trust * settled
        let blended = confidence * estimate + (1 - confidence) * baselineHours
        let hours = Swift.min(blended, learnedCeilingHours)
        // Reported against the number actually returned, not the one before the ceiling.
        // A ten-hour sleeper's estimate is clamped to 9.5, of which only 0.47 was theirs,
        // and the sentence was still claiming all of it came from their own nights.
        let spread = estimate - baselineHours
        let used = abs(spread) < 1e-9 ? confidence
            : Swift.min(1, Swift.max(0, (hours - baselineHours) / spread))
        return LearnedNeed(hours: hours, confidence: used)
    }

    /// How wide a slice of the distribution the estimate averages over.
    public static let needBand = 0.06

    /// How far ABOVE the floor the blend runs.
    ///
    /// The ramp used to sit below the floor, which inverted its purpose: it was added to
    /// kill a twelve-point cliff and instead handed a flat 6.9-hour sleeper a need of
    /// 7.12 and a permanent green, while a weekday/weekend sleeper getting more sleep on
    /// average sat non-green on 43 nights out of 60. Blending upward keeps the curve
    /// continuous without lowering the bar for exactly the person the floor exists for.
    public static let learnedRampHours = 0.75

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
    public static func of(baseline: Double = baselineHours, learnedShare: Double = 0,
                          strain: Double? = nil, napHours: Double? = nil) -> SleepNeed {
        let baseline = baseline.isFinite
            ? Swift.min(Swift.max(baseline, minimumHours), maximumHours) : baselineHours
        let adjustment = strain.map {
            Swift.max(0, ($0 - strainThreshold) / (StrainScore.scaleMax - strainThreshold))
                * strainExtraHours
        } ?? 0
        let nap = Swift.min(Swift.max(0, napHours ?? 0), maximumNapCreditHours)
        return SleepNeed(hours: clamp(baseline + adjustment - nap),
                         baseline: baseline,
                         strainAdjustment: adjustment, napCredit: nap,
                         learnedShare: Swift.min(1, Swift.max(0, learnedShare)))
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
    /// Outstanding hours, never negative: sleeping extra pays the hole down and then
    /// stops. Being twelve hours "ahead" is not a thing anybody can spend.
    public let hours: Double
    /// Signed change from the night before. Negative is progress.
    public let change: Double
    public let nights: Int

    /// How many hours in the hole count as one standard deviation of bad news.
    ///
    /// Debt is scored absolutely rather than against the sleeper's own rolling average,
    /// which is the whole point of the constant existing. A stock has almost no
    /// day-to-day variance to divide by: measured over sixty days its deviation was
    /// minutes, and for a chronically short sleeper pinned at the cap it was exactly
    /// zero, leaving thirty per cent of recovery's weight inert. Worse, scoring an
    /// absolute-bad quantity against its own mean inverts it: sitting at eight hours
    /// down read as *good news* because it was slightly below an elevated normal.
    ///
    /// Owing nothing is good for everybody, so zero is the anchor and the scale is
    /// stated.
    ///
    /// Six hours, not three, because of where the per-input clamp bites: debt carries a
    /// weight of 0.30 against a limit of 0.35, so it saturates at about 1.17 standard
    /// deviations however the scale is drawn. At three hours per deviation that put the
    /// ceiling at three and a half hours behind: twelve hours in the hole scored no
    /// worse, and the metric graded over a range narrower than a single bad week. At
    /// six it grades across the seven hours that actually distinguish people, and
    /// flattens only where further distinctions stop mattering.
    public static let hoursPerDeviation = 6.0

    /// How much of yesterday's balance is still owed today.
    ///
    /// Replaces a hard seven-night window, which had an edge: a night stopped counting
    /// entirely on its eighth day. After a bad week that produced five mornings where
    /// ideal sleep moved the recovery ring not at all, and then eighteen points across two
    /// mornings as the worst night fell off the back: 32 / 32 / 32 / 32 / 32 / 41 / 50,
    /// crossing a band, caused by nothing the sleeper did. Widening the window to a
    /// fortnight smoothed it and pinned a short sleeper at the cap on 82% of days instead
    /// of 29%, so neither width was right; the edge was the problem, not its position.
    ///
    /// Nights now fade instead of dropping. At 0.85 a night is half forgotten after about
    /// four and a half, and effectively gone after a fortnight, which is close to the old
    /// window's reach without its cliff. It also repairs something the window quietly got
    /// wrong: against a fixed window, sleeping *exactly* your own median paid back nothing
    /// at all, because the balance only moved when a night entered or left. Now a night
    /// that adds nothing still lets what is owed decay.
    public static let retention = 0.85

    /// A real ceiling rather than a scoring convenience. Past this the number stops
    /// being information and starts being an accusation.
    ///
    /// Seven rather than twelve, because that is where recovery stops being able to hear
    /// it: a 0.30-weight input against a 0.35 clamp saturates at `hoursPerDeviation`
    /// times 1.17, which is seven hours. At twelve, the top 42% of the displayed range
    /// scored identically: somebody forty nights into a six-hour habit could sleep nine
    /// hours twice and watch the ring not move, with the advice still reading "reduce".
    /// The number shown and the number scored should agree.
    public static let maximumHours = 7.0

    /// `nights` is hours slept, oldest first, ending with last night.
    /// What the balance accrues against.
    ///
    /// NOT the score's need. The score asks "did last night meet what you need", and the
    /// need for that is the upper part of your own distribution: above your average by
    /// construction. Accumulating against it over a fortnight multiplies that bias by
    /// fourteen: measured, somebody averaging a solid eight hours carried a standing
    /// balance of 4.2 hours and an ordinary weekday/weekend sleeper sat pinned at the
    /// twelve-hour cap on 53 days out of 60. The number was a statement about their
    /// variance, not their sleep.
    ///
    /// Their own median is unbiased: a steady sleeper owes nothing, a bad week shows,
    /// a recovery week pays down. Floored at seven hours so the one case a self-relative
    /// reference cannot see is still caught: somebody chronically short has a median
    /// that ratifies the shortage, and their debt would otherwise read zero forever.
    static func reference(for nights: [Double]) -> Double {
        let usable = nights.filter { $0.isFinite && $0 > 0 }.sorted()
        guard !usable.isEmpty else { return SleepNeed.baselineHours }
        let middle = usable.count / 2
        let median = usable.count.isMultiple(of: 2)
            ? (usable[middle - 1] + usable[middle]) / 2 : usable[middle]
        return Swift.max(median, SleepNeed.learnedFloorHours)
    }

    /// How many *recorded* nights the reference rests on.
    ///
    /// Recorded, not calendar, and this is the one place in the balance that counts
    /// readings rather than days. The decay has to run per night that passed, or a week
    /// away freezes what is owed. The reference is the opposite: it is a median, the
    /// statistic most prone to stepping on a small sample, and pinning it to a run of
    /// calendar nights left it resting on eight readings for somebody wearing the watch
    /// twice a week. It then re-levelled overnight: a four-nights-a-week wearer saw
    /// 7.0 h behind, then 5.5, then 4.1 on three mornings of identical sleep, with the
    /// arrow pointing up each time and the ring gaining seven points.
    public static let referenceNights = 28

    /// The most credit a run of long nights can bank. Some, because a floor at zero
    /// stops a good night paying anything down and turns the balance into a ratchet,
    /// but not unbounded, because a fortnight of holiday is not a licence.
    public static let maximumCreditHours = 3.0

    /// `nights` is hours slept, one entry per calendar night, oldest first, nil on a
    /// night nothing was recorded.
    ///
    /// The nils matter. The decay used to be applied once per array entry, and the array
    /// arrived with its unrecorded nights already compacted out, so taking the watch off
    /// *froze* the balance rather than letting it fade, and a week away left somebody
    /// carrying a balance a fortnight of ordinary sleep should have cleared. Worth about
    /// fourteen points of recovery ring after a fortnight's gap, and it made the sentence
    /// on screen ("each night fades as it recedes") false for exactly the people most
    /// likely to be reading it.
    ///
    /// A night nobody recorded fades what is owed and contributes nothing of its own,
    /// not wearing the watch is neither a good night nor a bad one.
    public static func of(nights: [Double?]) -> SleepDebt {
        let clean: [Double?] = nights.map { night in
            guard let night, night.isFinite, night >= 0 else { return nil }
            return night
        }
        // One reference for both balances, and the same fourteen-night window ending a
        // night apart. Re-learning it between the two made the arrow disagree with the
        // number above it on 66 days out of 70, and point the wrong way on 27.
        let against = reference(for: Array(clean.compactMap { $0 }.suffix(referenceNights)))
        let balance = accumulate(clean, against: against)
        // Yesterday's balance as yesterday computed it, against yesterday's own reference.
        //
        // So `change` is the difference between two consecutive cards, which is the only
        // thing a reader can check. Measuring both against today's reference made the two
        // internally consistent and disagreeing with what the person actually saw: the
        // reference moves as nights enter and leave the sample, and for a sparse wearer
        // near steady state that shift is larger than the night's own contribution, so the
        // arrow pointed up on a morning the number had fallen. This has now been the wrong
        // way round twice; defining it as what it claims to be settles it.
        let yesterday = Array(clean.dropLast())
        let previous = accumulate(yesterday, against: reference(
            for: Array(yesterday.compactMap { $0 }.suffix(referenceNights))))
        return SleepDebt(hours: Swift.max(0, balance),
                         change: Swift.max(0, balance) - Swift.max(0, previous),
                         nights: clean.compactMap { $0 }.count)
    }

    /// The balance as it ran, one point per night, ending with today's.
    ///
    /// For drawing. `of` cannot be walked over a growing prefix to get this, which is how
    /// the chart came to disagree with the number above it: `of` learns its reference from
    /// every night it is handed, so each prefix produced a different one, ending at the
    /// whole record's median while the row was reading the last `points` nights'. A
    /// settled sleeper whose habit had changed months ago saw a line pinned at the cap for
    /// twenty-three of its twenty-eight points under a row saying they owed nothing.
    ///
    /// One reference, taken from the same nights the row reads, so a rise on this line
    /// means less sleep and never a reference that moved underneath it.
    public static func history(nights: [Double?], points: Int) -> [Double] {
        let clean: [Double?] = nights.map { night in
            guard let night, night.isFinite, night >= 0 else { return nil }
            return night
        }
        guard clean.contains(where: { $0 != nil }), points > 0 else { return [] }
        let against = reference(for: Array(clean.compactMap { $0 }.suffix(referenceNights)))
        // The same span and the same reference the row uses, so the line ends exactly
        // where the number says. With decay the starting point barely matters after a
        // fortnight, but "barely" is not "exactly", and these two have disagreed before.
        let balances = clean.indices.map { end in
            Swift.max(0, accumulate(Array(clean[...end]), against: against))
        }
        return Array(balances.suffix(points))
    }

    private static func accumulate(_ nights: [Double?], against reference: Double) -> Double {
        guard !nights.isEmpty else { return 0 }
        var debt = 0.0
        for slept in nights {
            // A night that passed unrecorded still passed: it fades what is owed and adds
            // nothing of its own.
            guard let slept else {
                debt *= retention
                continue
            }
            debt = Swift.min(maximumHours,
                             Swift.max(-maximumCreditHours,
                                       debt * retention + (reference - slept)))
        }
        return debt
    }
}

public struct SleepInput: Sendable {
    public let breakdown: SleepBreakdown?
    public let durationHours: Double?
    /// Trailing nights, for judging tonight's structure against this sleeper's own.
    public let history: [SleepBreakdown]
    /// Hours slept on the nights behind this one, for learning what this person needs.
    public let priorNights: [Double]
    /// Yesterday's strain, 0...100.
    public let strain: Double?
    public let napHours: Double?
    public let sleepingHeartRate: Double?
    /// The waking, non-active average, which is what the dip is measured against.
    public let daytimeHeartRate: Double?
    public let calendar: Calendar

    public init(breakdown: SleepBreakdown?, durationHours: Double?,
                history: [SleepBreakdown] = [], priorNights: [Double] = [],
                strain: Double? = nil, napHours: Double? = nil,
                sleepingHeartRate: Double? = nil, daytimeHeartRate: Double? = nil,
                calendar: Calendar = .current) {
        self.breakdown = breakdown
        self.durationHours = durationHours
        self.history = history
        self.priorNights = priorNights
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
/// within a narrow band, the way AutoSleep's quality does. But every structural
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
    /// Was 0.85, which is exactly where `ScoreBand.sleep` turns green, so the worst
    /// possible structure on a full-length night still landed at 85 and read as a good
    /// one. 0.80 did not fix it either: the same night, three hours awake with no deep
    /// sleep, no REM and no overnight heart rate drop, still scored 85.7. At 0.70 it
    /// reads 78.6, and the cost to an ordinary night is two hundredths of a point.
    public static let qualityFloor = 0.70

    /// Below this, unlabelled time is a few stray minutes at the edges of a record and
    /// saying so every morning is noise rather than honesty.
    public static let minimumUnlabelledToMention = 0.25

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

    /// - Parameter wearsAWatch: whether anything on this person can record stages and an
    ///   overnight heart rate. False excludes those rows from the missing list entirely
    ///   rather than listing them as absent today: "wear your watch" is advice, and
    ///   advice somebody cannot take is noise they read every morning for ever.
    public static func of(_ input: SleepInput, wearsAWatch: Bool = true) -> SignalScore {
        let hours = input.durationHours ?? input.breakdown?.recordedSleepHours
        guard let hours, hours.isFinite, hours > 0 else {
            return SignalScore(kind: .sleep, value: nil, band: nil, contributors: [],
                               coverage: .unavailable, missing: ["Sleep"],
                               neutral: perfect, modelVersion: modelVersion)
        }

        let learned = SleepNeed.baseline(from: input.priorNights)
        let need = SleepNeed.of(baseline: learned.hours, learnedShare: learned.confidence,
                                strain: input.strain, napHours: input.napHours)
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

        // Two different reasons a component can be missing, and they are not the same
        // thing to say. "Still learning your normal" means give it time; a night the watch
        // did not finish labelling will not be fixed by waiting, and for a two-source user
        // whose second app brackets the night it never resolves at all. That message used
        // to appear for somebody with a fortnight of perfect stage history whose only
        // problem was that last night was 96% classified.
        let stagedNights = input.history.filter { $0.reconciledStages != nil }.count
        // Whether the *record* is short, which is what "still learning your normal" says.
        // It used to mean "too few staged nights", and a phone with no stage sensors never
        // gets one, so the commonest first-run profile there is was told the app was
        // still learning their normal every morning, for ever, with four reasons listed
        // that could never be satisfied. A phone-only record of sixty nights is not thin;
        // it is complete for what that device can see, which is what `.partial` says.
        let historyIsThin = input.history.count < BaselineSummary.minimumReadings
        // And the stage rewrite only makes sense where staging normally works.
        let stagingUsuallyWorks = stagedNights >= BaselineSummary.minimumReadings
        let tonightUnstaged = input.breakdown.map { $0.reconciledStages == nil } ?? false

        // A stream nothing on this person records is not absent today, it is absent
        // permanently, and the two read identically until one of them is dropped.
        let absent = components.filter { component in
            guard component.fraction == nil else { return false }
            return wearsAWatch || !needsAWatch(component)
        }
        // Nothing here has ever staged a night, so the seven nights the stage rows ask
        // for will not arrive: the record is not short, it is unstructured. Three rows
        // each promising that wait is the same untrue thing said three times, under
        // every night, for ever. One cause gets one line.
        let neverStaged = tonightUnstaged && stagedNights == 0
        var missing: [String] = []
        var saidStages = false
        for component in absent {
            let isStage = component.missingLabel.localizedCaseInsensitiveContains("stage data")
            if isStage, neverStaged {
                if !saidStages {
                    missing.append("Sleep stages, which nothing recording your nights "
                                 + "is measuring")
                    saidStages = true
                }
                continue
            }
            // Same row, right reason. The stage rows are absent because of last night,
            // not because the record is too short to judge it against.
            if isStage, tonightUnstaged, stagingUsuallyWorks {
                missing.append("\(component.title) last night, which your watch did not "
                             + "finish recording")
                continue
            }
            missing.append(component.missingLabel)
        }
        // The night was broken down, and part of it still carried no label. That part
        // was counted as light sleep, which is a choice and not a measurement, so it
        // gets said: a night measured light and a night nothing finished reading look
        // identical on the ring and are not the same thing.
        if let night = input.breakdown, night.stagedHours > 0,
           night.unlabelledHours >= minimumUnlabelledToMention {
            let hours = night.unlabelledHours.formatted(.number.precision(.fractionLength(1)))
            missing.append("Stage labels for \(hours) h of the night, counted as light")
        }

        let measured = components.count - absent.count
        // Decided in the spec: a phone-only sleeper can see a complete score. Their
        // record is complete for the device they own, and never being able to see a
        // full ring is the actual complaint.
        let coverage: ScoreCoverage = missing.isEmpty
            ? .full : (measured <= 2 && historyIsThin ? .buildingBaseline : .partial)
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
        /// terms: "0.5 h against the 1 h a night this long usually gives you" is a
        /// different sentence from "below your normal", and only the engine knows which
        /// of the two it means.
        var note: String? = nil
    }

    /// Whether a component can only ever be filled by something worn on the wrist.
    ///
    /// Read off the row's own missing label rather than a second list of component ids,
    /// so a component added to the model cannot quietly fall out of this.
    private static func needsAWatch(_ component: Component) -> Bool {
        let label = component.missingLabel.lowercased()
        return label.contains("stage") || label.contains("heart rate")
    }

    static func quality(_ input: SleepInput) -> [Component] {
        let night = input.breakdown
        let asleep = night?.asleepHours ?? 0

        /// Whether a night's stages can be trusted.
        ///
        /// Two ways they cannot. A night recorded as plain "asleep" has no stages at all,
        /// and that is not the same as a night with no deep sleep in it: the app used to
        /// tell somebody whose watch was on the charger that they got zero hours of REM
        /// and rank it as the reason their night was poor. And a phone and a watch both
        /// recording can report more staged hours than the night contained, which
        /// `HealthSource` already refuses to split but the scorer did not: one probe drew
        /// a ring reading "Deep 7.0 h" on a seven-hour night, arcs summing to 129% of it.
        func isStaged(_ night: SleepBreakdown) -> Bool {
            night.reconciledStages != nil
        }
        /// What the shares are taken against.
        ///
        /// Two devices each union their own samples and the totals are then summed, so a
        /// phone and a watch both recording can report more staged hours than the night
        /// contained. Rejecting those nights outright starved every structural component
        /// (of tonight AND of the whole history) so a second tracker cost nine points
        /// and a "still learning your normal" notice that never resolved. Scaling to fit
        /// keeps the proportions, which is the part that was ever being scored.
        let staged = night.map(isStaged) ?? false

        /// A stage as a share of the night it belonged to. The denominator is what
        /// carried a stage, not the night, so the same night with less of it labelled
        /// gives the same shares.
        func share(_ keyPath: KeyPath<SleepBreakdown, Double>) -> Double? {
            guard let night, asleep > 0, staged, night.stagedHours > 0 else { return nil }
            return night[keyPath: keyPath] / night.stagedHours
        }

        /// The same stage hours the scoring above used, for publishing.
        ///
        /// A stage row used to score a reconciled share and then report the raw hours
        /// beside it, which is two different nights in one row: the ring drew 3.0 hours
        /// of deep sleep where 1.96 had been scored, and the key printed it. It also made
        /// a row read "REM 1.65 h, your usual 1.65 h" and rank itself the night's worst
        /// component, because `comparison` is a share of the night and `value` was not.
        ///
        /// Note that `awakeHours` is deliberately not reconciled: it sits outside
        /// `asleepHours` and outside this denominator, and it is already scored raw.
        func reconciled(_ keyPath: KeyPath<SleepBreakdown, Double>) -> Double? {
            guard let night, night.stagedHours > 0 else { return nil }
            // Down only, matching `reconciledStages`. A night nothing finished labelling
            // reports the hours it recorded rather than a share of hours it did not.
            return night[keyPath: keyPath] * Swift.min(1, night.asleepHours / night.stagedHours)
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
                past.stagedHours > 0 ? past[keyPath: keyPath] / past.stagedHours : nil
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
                // Not "sleep stages, so continuity could not be read": continuity goes
                // nil for reasons that leave the stages perfectly intact, two separate
                // sleep episodes in one day, or two devices whose awake and asleep samples
                // conflict. That label appeared underneath a ring drawn from those very
                // stages.
                // Not "your devices did not agree": that is one of the reasons this
                // goes nil, and on a record with no stages in it there is no second
                // device and no disagreement, only a night stored as one undivided
                // block. The label has to hold every case it appears under.
                missingLabel: "One continuous record of the night, which nothing "
                            + "recorded end to end",
                symbol: "moon.zzz.fill",
                note: continuityFraction.map {
                    $0 >= 0.95 ? "You barely stirred."
                        : ($0 >= 0.85 ? "Broken up a little, but mostly solid."
                                      : "You spent a fair bit of the night not asleep.")
                }),
            Component(
                id: "schedule", title: "Bedtime",
                fraction: schedule.fraction,
                // The distance from the bedtime this person actually keeps, which the
                // tile has to say or the number means nothing: "Bedtime, 103.5 min"
                // reads as a duration of bedtime. Whole minutes, because half a minute
                // of bedtime is a precision no one has.
                value: schedule.medianMinutes.map { $0.rounded() }, unit: "min off usual",
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
                value: reconciled(\.deepHours), unit: "h",
                comparison: deepUsual, comparisonLabel: "your usual",
                explanation: "The share of the night spent in deep sleep, measured "
                           + "against your own nights rather than an ideal. There is no "
                           + "agreed correct amount, and anybody who tells you there is "
                           + "made it up. But a night well below your own usual is "
                           + "worth knowing about.",
                missingLabel: "Seven nights of stage data for deep sleep",
                symbol: "moon.fill",
                note: deepUsual.map { "A night this long usually gives you \(hours($0))." }),
            Component(
                id: "rem", title: "REM sleep",
                fraction: relative(share(\.remHours), historicShares(\.remHours),
                                   floor: shareDeviationFloor),
                value: reconciled(\.remHours), unit: "h",
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
                    $0 >= fullDip ? "A big drop: your body settled properly."
                        : ($0 >= 0.10 ? "A normal drop."
                        : ($0 >= 0.05 ? "A smaller drop than usual."
                                      : "Your heart rate stayed high for a night's rest."))
                }),
        ]
    }

    private static func needExplanation(_ need: SleepNeed) -> String {
        // Three states, because the baseline has three: assumed, still settling, and
        // learned. It used to have two, and called a blend "what your own nights take".
        let source: String
        switch need.learnedShare {
        case ..<0.05:
            source = "as a starting point until your own nights say otherwise"
        case 0.95...:
            source = "from what your own longest nights take"
        default:
            source = "still easing from the eight-hour starting point toward what your "
                   + "own longest nights take"
        }
        var parts = ["Your need last night was \(format(need.hours)) hours: "
                     + "\(format(need.baseline)) " + source]
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
