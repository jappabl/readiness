import Foundation

struct AssembledDay {
    let date: Date
    let readiness: ReadinessResult
    let readings: [MetricReading]
    let wristTemperatureDeviationC: Double?
    let multiDayTrendPresent: Bool
    let daysOfHistory: Int
}

/// Turns a run of daily physiology into today's readiness, by way of each metric's
/// own rolling baseline. The only place the two engines are composed.
enum DayAssembler {

    /// Hours of sleep treated as the nightly requirement for the readiness model's
    /// sleep-debt input.
    ///
    /// Deliberately `SleepNeed.baselineHours` rather than a second constant: the app had
    /// two different answers to "how much sleep do you need", one fixed at eight here and
    /// one dynamic in `SleepScore`, and they were both on screen at once.
    static let sleepNeedHours: Double = SleepNeed.baselineHours

    /// The debt reading, scored against zero rather than against the sleeper's own
    /// average debt.
    ///
    /// Every other metric here is a fluctuating measurement with a meaningful personal
    /// normal, and a z-score is the right tool for those. Debt is neither: it is a slow
    /// stock whose rolling deviation is minutes, and it has a true zero that means the
    /// same thing for everybody. Scored relatively it inverted — being eight hours down
    /// read as good news because it sat under an elevated mean — and for a chronic case
    /// pinned at the cap its deviation was exactly zero, so it stopped voting entirely.
    /// The same twenty-eight nights the card and the score read, so all three agree.
    static let debtNights = 28

    private static func debtReading(_ series: [DailyPhysiology]) -> MetricReading? {
        let all = series.compactMap(\.sleepHours)
        guard all.count >= 2 else { return nil }
        let debt = SleepDebt.of(nights: Array(all.suffix(debtNights)))
        return MetricReading(kind: .sleepDebt,
                             value: debt.hours,
                             // Owing nothing is the target, for everybody.
                             baseline: 0,
                             zScore: debt.hours / SleepDebt.hoursPerDeviation,
                             // How much history stands behind it, not how far the
                             // balance looks back — those were only ever the same
                             // number by coincidence, and the window has moved.
                             sampleCount: all.count)
    }

    static func assemble(series: [DailyPhysiology], acwr: Double? = nil) -> AssembledDay? {
        guard let today = series.last else { return nil }

        var readings: [MetricReading] = []
        var trendReadings: [MetricReading] = []

        func add(_ kind: MetricKind, _ values: [Double?]) {
            // A metric only votes on days it actually recorded.
            let present = values.compactMap { $0 }
            guard present.count == values.count, values.count >= 2 else {
                // Fall back to the days that do exist, so one missing night does not
                // silence a whole metric.
                let compacted = values.compactMap { $0 }
                guard compacted.count >= 2, values.last.flatMap({ $0 }) != nil,
                      let r = BaselineEngine.reading(kind: kind, series: compacted),
                      let full = BaselineEngine.evaluate(series: compacted) else { return }
                readings.append(r)
                trendReadings.append(MetricReading(kind: kind, value: r.value, baseline: r.baseline,
                                                   zScore: full.trendZScore, sampleCount: r.sampleCount))
                return
            }
            guard let r = BaselineEngine.reading(kind: kind, series: present),
                  let full = BaselineEngine.evaluate(series: present) else { return }
            readings.append(r)
            trendReadings.append(MetricReading(kind: kind, value: r.value, baseline: r.baseline,
                                               zScore: full.trendZScore, sampleCount: r.sampleCount))
        }

        add(.hrv, series.map(\.hrvSDNN))
        add(.restingHeartRate, series.map(\.restingHeartRate))
        // The running balance, on its own absolute scale — see `debtReading`.
        if let debt = debtReading(series) {
            readings.append(debt)
            trendReadings.append(debt)
        }
        add(.respiratoryRate, series.map(\.respiratoryRate))
        add(.bloodOxygen, series.map(\.bloodOxygenPercent))

        // HealthKit stores an absolute sleeping wrist temperature, not a deviation.
        // The deviation is only meaningful against this user's own baseline.
        var wristDeviation: Double?
        let wristSeries = series.compactMap(\.wristTemperatureC)
        if wristSeries.count >= 14, let result = BaselineEngine.evaluate(series: wristSeries),
           let current = today.wristTemperatureC {
            wristDeviation = current - result.mean
        }

        let daysOfHistory = series.count

        let trendResult = ReadinessEngine.evaluate(
            ReadinessInput(readings: trendReadings, daysOfHistory: daysOfHistory))
        let trendPresent = abs(trendResult.composite) >= 0.5

        let readiness = ReadinessEngine.evaluate(
            ReadinessInput(readings: readings,
                           wristTemperatureDeviationC: wristDeviation,
                           acwr: acwr,
                           daysOfHistory: daysOfHistory))

        return AssembledDay(date: today.date, readiness: readiness, readings: readings,
                            wristTemperatureDeviationC: wristDeviation,
                            multiDayTrendPresent: trendPresent,
                            daysOfHistory: daysOfHistory)
    }
}
