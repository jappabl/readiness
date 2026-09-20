import Foundation

/// One day's physiology, already reduced to daily aggregates.
/// Raw timeseries never travel past this boundary (spec 3.2).
///
/// Every field here is read from HealthKit, which means it works the same whether the
/// numbers came from an Apple Watch, an Oura ring or a Garmin — the app scores each
/// stream against the user's own history, so it never needs a vendor's own score.
struct DailyPhysiology: Sendable, Equatable {
    var date: Date

    // What the readiness model scores.
    var hrvSDNN: Double?
    var restingHeartRate: Double?
    var sleepHours: Double?
    var respiratoryRate: Double?
    var bloodOxygenPercent: Double?
    var wristTemperatureC: Double?
    var bodyTemperatureC: Double?

    // The night in detail: stages, time awake, time merely in bed.
    var sleep: SleepBreakdown?

    // Cardiac, beyond the resting number.
    var heartRateAverage: Double?
    var heartRateMin: Double?
    var heartRateMax: Double?
    var walkingHeartRateAverage: Double?
    var heartRateRecovery: Double?
    var vo2Max: Double?

    // Movement.
    var steps: Double?
    var activeEnergyKcal: Double?
    var basalEnergyKcal: Double?
    var exerciseMinutes: Double?
    var standMinutes: Double?
    var distanceKm: Double?
    var flightsClimbed: Double?
    var timeInDaylightMinutes: Double?

    // Body composition.
    var bodyMassKg: Double?
    var bodyFatPercent: Double?
    var leanBodyMassKg: Double?

    // Intake.
    var dietaryEnergyKcal: Double?
    var proteinGrams: Double?
    var carbohydrateGrams: Double?
    var fatGrams: Double?
    var waterLiters: Double?
    var caffeineMg: Double?
    var alcoholicDrinks: Double?

    // The day's heart rate in buckets, which is what a load model needs: an average and
    // a maximum cannot tell forty hard minutes from a steady walk that reached the same
    // peak. Empty means it was never fetched or the watch was off, never a quiet day.
    var heartRateSamples: [HeartRateSample] = []

    /// Averaged over the night's sleep window, and over the waking hours that were not
    /// exercise. The pair is the overnight dip, which is the single clearest sign a night
    /// was restorative rather than merely long.
    var sleepingHeartRate: Double?
    var wakingHeartRate: Double?

    // Training as the watch saw it, which is not the same as what the user logged here.
    var workoutCount: Int?
    var workoutMinutes: Double?
    var workoutEnergyKcal: Double?

    var mindfulMinutes: Double?
}

extension DailyPhysiology {
    /// Sleep and the other available signals remain useful without HRV or resting HR.
    var hasReadinessData: Bool {
        MetricKind.allCases.contains { value(for: $0) != nil }
            // Named rather than reached through `value(for: .sleepDebt)`, which no longer
            // answers: sleep is most of the time the only stream an iPhone-only user has,
            // and it still has to count as having data.
            || sleepHours != nil || wristTemperatureC != nil
    }

    /// The scored metrics, by kind, so a chart can be drawn for whichever one the coach
    /// points at without a switch at every call site.
    func value(for kind: MetricKind) -> Double? {
        switch kind {
        case .hrv:              return hrvSDNN
        case .restingHeartRate: return restingHeartRate
        case .respiratoryRate:  return respiratoryRate
        case .bloodOxygen:      return bloodOxygenPercent
        // A balance is a property of a run of nights, not of any one of them, so this
        // accessor cannot answer for it and no longer pretends to. It used to return
        // `8 - last night`: a different quantity, on a different scale, with a different
        // zero. Drawn under the title "Sleep debt" it told a chronic six-hour sleeper
        // they were two hours down and sitting exactly on their own normal, which reads
        // as nothing to see. `SleepDebt.of(nights:)` is the only thing that knows.
        case .sleepDebt:        return nil
        }
    }
}

enum HealthSourceError: LocalizedError {
    case unavailable
    case denied

    var errorDescription: String? {
        switch self {
        case .unavailable: return "Health data isn't available on this device."
        case .denied: return "Health access was declined."
        }
    }
}

/// Everything upstream reads this, never HealthKit directly. That is what lets a
/// synthetic simulator source and a real Apple Watch history be interchangeable.
protocol HealthSource: Sendable {
    func requestAuthorization() async throws
    /// Daily aggregates, oldest first, covering the last `days` days.
    func dailySeries(days: Int) async throws -> [DailyPhysiology]
}


extension DailyPhysiology {
    /// Every supported stream has a direct use in coaching; no raw samples leave here.
    static func coachHealthContext(_ days: [DailyPhysiology], today: Date = Date(),
                                   sleepTargetHours: Double = SleepNeed.baselineHours) -> HealthContext {
        let fields: [(String, String, KeyPath<DailyPhysiology, Double?>)] = [
            ("HRV SDNN", "ms", \.hrvSDNN), ("Resting HR", "bpm", \.restingHeartRate),
            ("Sleep", "h", \.sleepHours), ("Respiration", "/min", \.respiratoryRate),
            ("Blood oxygen", "%", \.bloodOxygenPercent), ("Sleeping wrist temp", "C", \.wristTemperatureC),
            ("Body temp", "C", \.bodyTemperatureC), ("Average HR", "bpm", \.heartRateAverage),
            ("Minimum HR", "bpm", \.heartRateMin), ("Maximum HR", "bpm", \.heartRateMax),
            ("Walking HR", "bpm", \.walkingHeartRateAverage), ("1min HR recovery", "bpm", \.heartRateRecovery),
            ("VO2 max", "ml/kg/min", \.vo2Max), ("Steps", "", \.steps),
            ("Active energy", "kcal", \.activeEnergyKcal), ("Resting energy", "kcal", \.basalEnergyKcal),
            ("Exercise", "min", \.exerciseMinutes), ("Standing", "min", \.standMinutes),
            ("Walk/run distance", "km", \.distanceKm), ("Flights climbed", "", \.flightsClimbed),
            ("Daylight", "min", \.timeInDaylightMinutes), ("Body mass", "kg", \.bodyMassKg),
            ("Body fat", "%", \.bodyFatPercent), ("Lean mass", "kg", \.leanBodyMassKg),
            ("Logged food energy", "kcal", \.dietaryEnergyKcal), ("Logged protein", "g", \.proteinGrams),
            ("Logged carbs", "g", \.carbohydrateGrams), ("Logged fat", "g", \.fatGrams),
            ("Logged water", "L", \.waterLiters), ("Logged caffeine", "mg", \.caffeineMg),
            ("Logged alcohol", "drinks", \.alcoholicDrinks),
            ("Health workout duration", "min", \.workoutMinutes), ("Health workout energy", "kcal", \.workoutEnergyKcal),
            ("Mindful sessions", "min", \.mindfulMinutes),
        ]
        var streams = fields.map { name, unit, path in
            HealthContext.Stream(name: name, unit: unit, observations: days.compactMap { day in
                day[keyPath: path].map { .init(date: day.date, value: $0) }
            })
        }
        let sleepFields: [(String, KeyPath<SleepBreakdown, Double>)] = [
            ("Core sleep", \.coreHours), ("Deep sleep", \.deepHours), ("REM sleep", \.remHours),
            ("Awake during sleep", \.awakeHours), ("In bed", \.inBedHours),
        ]
        for (name, path) in sleepFields {
            let isStage = name != "In bed" && name != "Awake during sleep"
            streams.append(.init(name: name, unit: "h", observations: days.compactMap { day in
                guard let night = day.sleep else { return nil }
                guard isStage else {
                    return night[keyPath: path] > 0
                        ? .init(date: day.date, value: night[keyPath: path]) : nil
                }
                // The same split the screen shows. This used to hand over the raw staged
                // hours and drop a night only when they overflowed it, so Jett was told
                // "deep sleep 0.9 h" about a night the app was showing as 1.2 — and was
                // told a number at all for nights the app says it cannot describe.
                guard night.reconciledStages != nil, night.stagedHours > 0 else { return nil }
                let value = night[keyPath: path] * (night.asleepHours / night.stagedHours)
                return value > 0 ? .init(date: day.date, value: value) : nil
            }))
        }
        streams.append(.init(name: "Health workouts", unit: "", observations: days.compactMap { day in
            day.workoutCount.map { .init(date: day.date, value: Double($0)) }
        }))
        return HealthContext.build(streams: streams, today: today,
                                   sleepTargetHours: sleepTargetHours)
    }
}
