import Foundation

/// The only health information that ever leaves the device.
///
/// Derived aggregates only — never raw samples, never a timeseries of measurements.
/// Kept small on purpose: a compact summary is both the privacy boundary and the thing
/// that decides whether a flat-priced coach is affordable.
public struct CoachContext: Codable, Equatable, Sendable {

    public struct MetricSummary: Codable, Equatable, Sendable {
        public let name: String
        public let value: Double
        public let baseline: Double
        public let z: Double
        public let unit: String
    }

    /// One of the three rings, as the person is looking at it.
    ///
    /// The block carried the model's internals — state, composite, per-metric z — and none
    /// of the three numbers actually on screen. With the hard rule "never invent a
    /// measurement; if a number is not in the block, say you do not have it", the correct
    /// behaviour was for Jett to say he could not see the user's recovery score while that
    /// score sat on the screen beside the chat.
    public struct ScoreSummary: Codable, Equatable, Sendable {
        public let name: String
        public let value: Int?
        public let band: String?
        /// Only when it is not the whole picture, so an ordinary day costs no bytes.
        public let caveat: String?

        public init(name: String, value: Int?, band: String?, caveat: String?) {
            self.name = name
            self.value = value
            self.band = band
            self.caveat = caveat
        }
    }

    public struct DaySummary: Codable, Equatable, Sendable {
        public let day: String
        public let state: String
        public let composite: Double
        public let volume: Double
    }

    public struct ExerciseSummary: Codable, Equatable, Sendable {
        public let name: String
        public let muscle: String
        public let sets: Int
        public let reps: Int
        public let weight: Double
        public let rir: Int
    }

    public let today: String
    public let state: String
    public let composite: Double
    public let confidence: String
    public let daysOfHistory: Int
    public let gate: String?
    public let metrics: [MetricSummary]
    public let checkIn: [String: Int]?
    public let acwr: Double?
    public let recentDays: [DaySummary]
    public let program: [ExerciseSummary]
    public let proposedAdjustments: [String]
    public let uncertainty: [String]
    public let goal: String?
    public let limitations: String?
    /// The three rings. `var` with a default so this is additive for every caller.
    public var scores: [ScoreSummary] = []
    /// What the sleep score measured last night against, in hours. The rules tell the
    /// model the need is learned "which the block states", so the block has to state it.
    public var sleepNeedHours: Double?
    public var health: HealthContext?
    public var profile: CoachProfileSummary?

    public static let maximumRecentDays = 14

    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    public var approximateBytes: Int { brief.utf8.count }

    /// What is actually sent to the model.
    ///
    /// The same facts as `json`, rendered as labelled lines instead of objects. JSON
    /// spends most of its bytes repeating key names — fourteen days of history cost a
    /// thousand bytes as objects and a third of that as rows — and every one of those
    /// bytes is both money and time-to-first-token, because the whole prompt has to be
    /// read before the first word comes back.
    ///
    /// Column headers are kept so nothing has to be inferred from position alone. The
    /// rendering is deterministic, which is what lets a provider's prefix cache hold
    /// from one turn to the next.
    public var brief: String {
        var lines: [String] = []

        lines.append("date \(today) | state \(state) | composite \(composite) | "
                     + "confidence \(confidence) | history \(daysOfHistory)d"
                     + (gate.map { " | gate \($0)" } ?? ""))
        if let acwr { lines.append("acute:chronic load \(acwr)") }
        if let goal { lines.append("goal \(goal)") }
        if let limitations { lines.append("limitations \(limitations)") }
        if let profile { lines.append(profile.brief) }
        if let checkIn {
            let reported = checkIn.keys.sorted().map { "\($0) \(checkIn[$0] ?? 0)/5" }
            lines.append("check-in (stress 1=maxed,5=calm): " + reported.joined(separator: ", "))
        }

        if !scores.isEmpty {
            lines.append("scores on screen now: " + scores.map { score in
                var text = score.name + " "
                text += score.value.map(String.init) ?? "unavailable"
                if let band = score.band { text += " " + band }
                if let caveat = score.caveat { text += " (" + caveat + ")" }
                return text
            }.joined(separator: ", "))
        }
        if let sleepNeedHours {
            lines.append("sleep need last night "
                         + sleepNeedHours.formatted(.number.precision(.fractionLength(1))) + "h")
        }

        lines.append("")
        lines.append("metrics (name value baseline z):")
        for metric in metrics {
            lines.append("\(metric.name) \(metric.value)\(metric.unit) "
                         + "base \(metric.baseline) z \(metric.z)")
        }

        if let health { lines.append("\n" + health.brief) }

        if !recentDays.isEmpty {
            lines.append("")
            lines.append("last \(recentDays.count) days (mm-dd state composite volume), "
                         + "oldest first:")
            for day in recentDays {
                lines.append("\(Self.monthDay(day.day)) \(day.state) \(day.composite) "
                             + "\(day.volume)")
            }
        }

        if !program.isEmpty {
            lines.append("")
            lines.append("today's session (exercise | muscle | sets x reps @ load | rir):")
            for exercise in program {
                lines.append("\(exercise.name) | \(exercise.muscle) | "
                             + "\(exercise.sets)x\(exercise.reps) @\(exercise.weight) | "
                             + "rir \(exercise.rir)")
            }
        }

        if !proposedAdjustments.isEmpty {
            lines.append("")
            lines.append("the engine proposes:")
            lines.append(contentsOf: proposedAdjustments.map { "- \($0)" })
        }

        if !uncertainty.isEmpty {
            lines.append("")
            lines.append("what this cannot see:")
            lines.append(contentsOf: uncertainty.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    /// "2026-09-01" to "09-01". The year is already on the header line.
    static func monthDay(_ isoDay: String) -> String {
        isoDay.count == 10 ? String(isoDay.dropFirst(5)) : isoDay
    }
}

public enum CoachContextBuilder {

    /// Rounds everything on the way out. Full float precision costs tokens and implies
    /// a certainty the measurements do not have.
    static func round(_ value: Double, places: Int = 2) -> Double {
        let factor = pow(10.0, Double(places))
        return (value * factor).rounded() / factor
    }

    public static func build(today: Date,
                             readiness: ReadinessResult,
                             readings: [MetricReading],
                             daysOfHistory: Int,
                             recommendation: Recommendation,
                             checkIn: CheckIn?,
                             acwr: Double?,
                             recentDays: [CoachContext.DaySummary],
                             program: [CoachContext.ExerciseSummary],
                             goal: String?,
                             limitations: String?,
                             describe: (SessionAdjustment) -> String) -> CoachContext {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current

        return CoachContext(
            today: formatter.string(from: today),
            state: recommendation.state.rawValue,
            composite: round(readiness.composite),
            confidence: readiness.confidence.rawValue,
            daysOfHistory: daysOfHistory,
            gate: readiness.gateApplied?.rawValue,
            metrics: readings.map {
                CoachContext.MetricSummary(name: $0.kind.rawValue,
                                           value: round($0.value, places: 1),
                                           baseline: round($0.baseline, places: 1),
                                           z: round($0.zScore),
                                           unit: $0.kind.unit)
            },
            checkIn: checkIn.map {
                ["soreness": $0.soreness, "energy": $0.energy,
                 "stress": $0.stress, "mood": $0.mood]
            },
            acwr: acwr.map { round($0) },
            recentDays: Array(recentDays.suffix(CoachContext.maximumRecentDays)),
            program: program,
            proposedAdjustments: recommendation.adjustments.map(describe),
            uncertainty: recommendation.uncertainty,
            goal: goal?.isEmpty == false ? goal : nil,
            limitations: limitations?.isEmpty == false ? limitations : nil)
    }
}


extension CoachContextBuilder {
    public static func withoutReadiness(today: Date, goal: String?, limitations: String?,
                                        checkIn: CheckIn?, acwr: Double?,
                                        program: [CoachContext.ExerciseSummary],
                                        health: HealthContext) -> CoachContext {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return CoachContext(today: formatter.string(from: today), state: "unknown",
                            composite: 0, confidence: "none", daysOfHistory: 0, gate: nil,
                            metrics: [], checkIn: checkIn.map {
                                ["soreness": $0.soreness, "energy": $0.energy,
                                 "stress": $0.stress, "mood": $0.mood]
                            }, acwr: acwr, recentDays: [], program: program,
                            proposedAdjustments: [],
                            uncertainty: ["No current readiness baseline. Zero composite is a placeholder, not a measurement. Use only the dated Health summaries that are available."],
                            goal: goal, limitations: limitations, health: health)
    }
}
