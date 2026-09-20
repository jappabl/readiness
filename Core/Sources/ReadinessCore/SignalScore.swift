import Foundation

/// The shape every signal's score comes back in.
///
/// Three engines, one structure, so the Insights screen is one screen. The rule this
/// buys is worth stating plainly: adding an input to an engine must show up in the app
/// without anybody editing a view. A breakdown that has to be maintained alongside the
/// model is a breakdown that will eventually describe a different model.
///
/// See docs/superpowers/specs/2026-09-19-signal-scores-design.md.

public enum SignalKind: String, Sendable, Codable, CaseIterable {
    case recovery, sleep, strain
}

/// The fixed meaning of a stretch of a signal's scale.
///
/// Bands are what make the scale absolute rather than relative: 67 is green today, was
/// green last month, and is green for somebody else. A band derived from the user's own
/// spread would be a percentile wearing a percent sign.
public enum ScoreBand: String, Sendable, Codable, Equatable {
    // Recovery and sleep, following the thresholds Whoop publishes.
    case red, yellow, green
    // Strain, on the 0...21 scale.
    case light, moderate, hard, allOut

    public static func recovery(percent: Double) -> ScoreBand {
        switch percent {
        case 67...: return .green
        case 34..<67: return .yellow
        default: return .red
        }
    }

    /// Stricter than recovery, because sleep is a share of what the night needed to be.
    /// Half your need is not an average night, it is a bad one.
    public static func sleep(percent: Double) -> ScoreBand {
        switch percent {
        case 85...: return .green
        case 70..<85: return .yellow
        default: return .red
        }
    }

    /// The same boundaries as the old 0-21 scale, at round numbers: 10, 14 and 18 of 21
    /// are 48, 67 and 86 of 100.
    public static func strain(value: Double) -> ScoreBand {
        switch value {
        case 85...: return .allOut
        case 70..<85: return .hard
        case 50..<70: return .moderate
        default: return .light
        }
    }
}

/// How a single input is doing, in the three steps a person can act on.
///
/// Oura's contributor list is the prior art and the useful part of it is exactly this:
/// a number alone tells you nothing, and a number with "pay attention" beside it tells
/// you where to look.
public enum ContributorState: String, Sendable, Codable, Equatable {
    case optimal, fine, payAttention

    /// From the aligned z — how far this reading sits from baseline in the direction
    /// that is good news. The band is deliberately wide: half a standard deviation is
    /// noise on most of these streams, and flagging it teaches people to ignore flags.
    static func from(alignedZ: Double) -> ContributorState {
        switch alignedZ {
        case 0.5...: return .optimal
        case ..<(-0.5): return .payAttention
        default: return .fine
        }
    }
}

public struct ScoreContributor: Sendable, Equatable, Codable, Identifiable {
    /// Stable across runs and releases, so a row can be diffed and tested by name.
    public let id: String
    public let title: String
    public let value: Double?
    public let unit: String
    /// What the value was judged against — the user's own baseline, or a target.
    public let comparison: Double?
    public let comparisonLabel: String?
    public let state: ContributorState
    /// How this row is doing on its own terms, 0...1, higher always better.
    ///
    /// The bar draws this and nothing else. Deriving a bar from `magnitude` looked
    /// reasonable and was wrong in both directions: on sleep a magnitude is a loss, so a
    /// row that cost nothing drew an empty bar and read as the worst one on screen.
    /// A row's own level is the only thing that means the same in every signal.
    public let level: Double?
    /// An SF Symbol name. The tile shows this instead of a sentence — a bed, a pair of
    /// lungs and a flame say what three lines of prose were saying, and say it faster.
    public let symbol: String
    /// The one sentence about this row, when the engine can say it better than a
    /// generic "against your normal of X" can. Nil lets the screen derive one from
    /// `value` and `comparison`, which is right for a plain physiological reading.
    public let note: String?
    /// Points of the final score this input moved, signed. These sum to the distance
    /// between the score and its neutral point, which is what lets the screen claim the
    /// rows explain the number.
    public let magnitude: Double
    public let explanation: String
    /// Oldest first, for the row's expandable chart. Empty is fine; a chart is an
    /// enrichment, not a precondition for showing the row.
    public let history: [Double]

    public init(id: String, title: String, value: Double?, unit: String,
                comparison: Double?, comparisonLabel: String?, state: ContributorState,
                level: Double? = nil, symbol: String = "circle.dashed",
                magnitude: Double, explanation: String,
                note: String? = nil, history: [Double] = []) {
        self.id = id
        self.title = title
        self.value = value
        self.unit = unit
        self.comparison = comparison
        self.comparisonLabel = comparisonLabel
        self.state = state
        self.level = level
        self.symbol = symbol
        self.note = note
        self.magnitude = magnitude
        self.explanation = explanation
        self.history = history
    }
}

public enum ScoreCoverage: String, Sendable, Codable, Equatable {
    /// Every input the model wanted was there.
    case full
    /// Something was missing. The score still stands, and `missing` names what is absent
    /// so the screen can say so rather than quietly showing a thinner number.
    case partial
    /// Not enough history to compare against yet.
    case buildingBaseline
    /// No score. Never a zero, never a fifty.
    case unavailable
}

public struct SignalScore: Sendable, Equatable, Codable {
    public let kind: SignalKind
    /// Nil only when coverage is `.unavailable`. A missing measurement is not a low one.
    public let value: Double?
    public let band: ScoreBand?
    /// Ranked by how much each one moved the score today.
    public let contributors: [ScoreContributor]
    public let coverage: ScoreCoverage
    /// Human-readable, for the coverage note.
    public let missing: [String]
    /// Where the contributors count from. Recovery starts at the middle of its scale and
    /// moves either way; strain accumulates from nothing; sleep is a full night you lose
    /// points against. The rows always sum to `value - neutral`, whichever it is, so the
    /// screen can render all three without knowing which signal it is looking at.
    public let neutral: Double
    /// Set when something overrode the weighted result. The screen has to show it, or
    /// the contributors will not explain the number they sit under.
    public let gate: ReadinessGate?
    public let modelVersion: String

    public func contributor(_ id: String) -> ScoreContributor? {
        contributors.first { $0.id == id }
    }

    /// One sentence naming what actually moved the number, or what is missing.
    ///
    /// Generic on purpose: it reads the contributors rather than knowing which signal it
    /// is describing, so a new input starts appearing here the day it starts counting.
    ///
    /// Never states the score. Every place this is shown already has the number next to
    /// it, and repeating it spends the one sentence saying what the reader can see.
    public var summary: String {
        guard value != nil else {
            guard let first = missing.first else { return "Nothing recorded for this yet." }
            return "Waiting on \(first.lowercased())."
        }
        // Five points, not one. One point of recovery is three minutes of sleep or a
        // tenth of a beat, so the sentence used to lead on pure noise — "heart rate
        // variability pushed it up most" off a 0.8 ms wobble.
        guard let lead = contributors.first, abs(lead.magnitude) >= 5 else {
            return gate.map { "\($0.displayName) is what matters today." }
                ?? "Nothing stood out today."
        }
        let direction = lead.magnitude > 0 ? "pushed it up" : "pulled it down"
        let detail: String
        if let measured = lead.value {
            let formatted = measured.formatted(.number.precision(.fractionLength(0...1)))
            if let comparison = lead.comparison, let label = lead.comparisonLabel {
                detail = " — \(formatted)\(lead.unit.isEmpty ? "" : " " + lead.unit) against "
                       + "\(label) of \(comparison.formatted(.number.precision(.fractionLength(0...1))))"
            } else {
                detail = " — \(formatted)\(lead.unit.isEmpty ? "" : " " + lead.unit)"
            }
        } else {
            detail = ""
        }
        return "\(lead.title) \(direction) most\(detail)."
    }

    public init(kind: SignalKind, value: Double?, band: ScoreBand?,
                contributors: [ScoreContributor], coverage: ScoreCoverage,
                missing: [String] = [], neutral: Double = 0,
                gate: ReadinessGate? = nil, modelVersion: String) {
        self.kind = kind
        self.value = value
        self.band = band
        self.contributors = contributors
        self.coverage = coverage
        self.missing = missing
        self.neutral = neutral
        self.gate = gate
        self.modelVersion = modelVersion
    }
}

/// Turns a readiness result into the number on the ring.
public enum RecoveryScore {

    /// The composite's own spread, stated rather than measured.
    ///
    /// The composite is a weighted mean of clamped z-scores whose weights sum to 1, so
    /// its standard deviation is `sqrt(Σw²)` before correlation — about 0.49 with the
    /// shipping weights, rising to roughly 0.83 if the inputs move together strongly.
    /// 0.6 is the middle of that range.
    ///
    /// It is a constant and not the user's own spread on purpose. Dividing by their own
    /// history would guarantee everybody the same distribution of green days, which is a
    /// percentile, not a score. Here a given physiological deviation always reads the
    /// same, for everyone — which is the whole claim an absolute scale makes.
    public static let compositeScale = 0.75

    /// The most a single input can move the composite on its own.
    ///
    /// Without it one metric could red-line the ring by itself: a resting heart rate two
    /// beats above normal, with every other reading exactly average, produced a 34 and a
    /// "reduce" order. No one measurement is worth that much, and the whole argument for
    /// a weighted composite is that they vote together.
    public static let contributionClamp = 0.35

    /// Below this share of the total weight, the composite is damped rather than
    /// renormalised to full confidence.
    ///
    /// Renormalising over whatever survived meant a single blood-oxygen reading 0.8
    /// points low — a 0.07-weight metric — produced exactly the same score as a full
    /// panel saying the same thing, because it inherited the entire vote of the four
    /// streams that were missing. It stops voting; it does not get to vote for everyone.
    public static let minimumConfidentWeight = 0.5

    /// Where the neutral day sits. Half the scale, by construction.
    public static let neutral = 50.0

    public static func percent(composite: Double) -> Double {
        guard composite.isFinite else { return composite > 0 ? 100 : 0 }
        return 100 * Percentile.fromZ(composite / compositeScale)
    }

    public static func of(_ result: ReadinessResult,
                          readings: [MetricReading] = [],
                          history: [MetricKind: [Double]] = [:]) -> SignalScore {
        guard !result.contributions.isEmpty else {
            return SignalScore(kind: .recovery, value: nil, band: nil, contributors: [],
                               coverage: .unavailable,
                               missing: [MetricKind.hrv.displayName],
                               modelVersion: result.modelVersion)
        }

        // The gate is the score, when there is one. A morning clamped for illness that
        // still displayed its ungated number would put a green ring above "recover".
        let ungated = percent(composite: result.composite)
        let value = result.gateApplied.map { min(ungated, ceiling(for: $0)) } ?? ungated

        let voted = Set(result.contributions.map(\.kind))
        let missing = ReadinessEngine.weights.keys
            .filter { !voted.contains($0) }
            .map(\.displayName)
            .sorted()

        // A thin baseline outranks a missing stream: it is the one that makes every
        // number softer. It used to be unreachable whenever anything was absent, so a
        // day-8 score was presented with exactly the confidence of a day-60 one.
        let coverage: ScoreCoverage
        if result.confidence == .low {
            coverage = .buildingBaseline
        } else if !missing.isEmpty {
            coverage = .partial
        } else {
            coverage = .full
        }

        return SignalScore(
            kind: .recovery,
            value: value,
            band: .recovery(percent: value),
            contributors: contributors(result, ungated: ungated, value: value,
                                       readings: readings, history: history),
            coverage: coverage,
            missing: missing,
            neutral: neutral,
            gate: result.gateApplied,
            modelVersion: result.modelVersion)
    }

    /// What each gate caps the score at.
    ///
    /// Illness is the bottom of the scale: the weighted inputs are no longer the story.
    /// A load spike is not — its own explanation says it "cannot make a good morning
    /// bad", and it used to take seventy-six points off one, producing a red ring above
    /// an at-baseline state and a "maintain". It caps at the top of yellow instead,
    /// which is what cancelling a green light actually means.
    static func ceiling(for gate: ReadinessGate) -> Double {
        switch gate {
        case .elevatedWristTemperature: return 8
        case .acuteLoadSpike: return 66
        }
    }

    private static func contributors(_ result: ReadinessResult, ungated: Double, value: Double,
                                     readings: [MetricReading],
                                     history: [MetricKind: [Double]]) -> [ScoreContributor] {
        // Attribution is proportional: each input moved the composite by its own points,
        // and the score sits `value - neutral` from the middle, so each input's share of
        // the composite is its share of that distance. This sums exactly, which is the
        // property the screen needs.
        //
        // The ratio stays finite as the composite approaches zero — the transfer's slope
        // at the origin is its limit — so inputs that cancel still report the push they
        // each made rather than collapsing to a row of zeros on the one day the
        // breakdown matters most.
        let slopeAtOrigin = 100 / (compositeScale * (2 * Double.pi).squareRoot())
        let ratio = abs(result.composite) < 1e-6
            ? slopeAtOrigin
            : (ungated - neutral) / result.composite

        var rows = result.contributions.map { contribution in
            let reading = readings.first { $0.kind == contribution.kind }
            let aligned = contribution.zScore * contribution.kind.polarity
            // `points` is already weighted and clamped, so dividing back out recovers
            // the aligned z the engine used.
            let scoringAligned = contribution.weight > 0
                ? contribution.points / contribution.weight : aligned
            return ScoreContributor(
                id: contribution.kind.rawValue,
                title: contribution.kind.displayName,
                value: reading?.value,
                unit: contribution.kind.unit,
                comparison: reading?.baseline,
                comparisonLabel: reading == nil ? nil : "your normal",
                // Both read the z the engine actually weighed, not today's raw one.
                // For HRV — the only metric scored on its trend — those differ, and the
                // row could show an alarming red dot beside a magnitude saying it barely
                // mattered, which is the screen arguing with itself.
                state: .from(alignedZ: scoringAligned),
                level: Percentile.fromZ(scoringAligned),
                symbol: contribution.kind.symbol,
                magnitude: contribution.points * ratio,
                explanation: contribution.kind.explanation,
                history: history[contribution.kind] ?? [])
        }
        .sorted { abs($0.magnitude) > abs($1.magnitude) }

        // The gate earns its own row, carrying whatever distance it moved the score that
        // the weighted inputs did not. Without it the rows would describe the morning the
        // user would have had, sitting under the number they actually got.
        // Only when it actually moved something. On a morning already below the
        // ceiling the gate changes nothing, and a zero-magnitude row at the top made
        // `summary` — which reads the leading row — announce "Nothing stood out today"
        // under the worst score the model can produce.
        if let gate = result.gateApplied, abs(value - ungated) > 0.01 {
            rows.insert(ScoreContributor(
                id: gate.rawValue,
                title: gate.displayName,
                value: nil,
                unit: "",
                comparison: nil,
                comparisonLabel: nil,
                state: .payAttention,
                symbol: gate == .elevatedWristTemperature ? "thermometer.high" : "bolt.trianglebadge.exclamationmark",
                magnitude: value - ungated,
                explanation: gate.explanation), at: 0)
        }
        return rows
    }
}
