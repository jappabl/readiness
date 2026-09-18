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

    /// Hours of sleep treated as the nightly requirement. A rolling personal estimate
    /// is a v0.2 refinement; a fixed need is honest and inspectable for v0.1.
    static let sleepNeedHours: Double = 8.0

    static func assemble(series: [DailyPhysiology]) -> AssembledDay? {
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
        add(.sleepDebt, series.map { $0.sleepHours.map { sleepNeedHours - $0 } })
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
                           acwr: nil,
                           daysOfHistory: daysOfHistory))

        return AssembledDay(date: today.date, readiness: readiness, readings: readings,
                            wristTemperatureDeviationC: wristDeviation,
                            multiDayTrendPresent: trendPresent,
                            daysOfHistory: daysOfHistory)
    }
}
