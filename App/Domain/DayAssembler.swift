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
    /// same thing for everybody. Scored relatively it inverted: being eight hours down
    /// read as good news because it sat under an elevated mean, and for a chronic case
    /// pinned at the cap its deviation was exactly zero, so it stopped voting entirely.
    /// The same twenty-eight nights the card and the score read, so all three agree.
    static let debtNights = 28

    /// How stale the sleep record may be before the balance stops being a measurement.
    /// A week: the decay's own memory is about that, so past it the number is a fade
    /// rather than an observation.
    static let recencyNights = 7

    private static func debtReading(_ series: [DailyPhysiology]) -> MetricReading? {
        // Dense by calendar night: an unrecorded night fades the balance rather than
        // freezing it, so the nights that passed have to be here.
        let all = series.map(\.sleepHours)
        let recorded = all.compactMap { $0 }
        guard recorded.count >= 2 else { return nil }
        // And something recorded *recently*. The balance decays per night that passed, so
        // a record that simply stops produces a number fading smoothly to zero, and zero
        // is this metric's best possible reading. Somebody who slept with the watch for two
        // months and then stopped ended up at 0.0 h, "You are not down on sleep", a full
        // green bar, an up arrow, `.optimal`, and coverage `.full`: the app fully confident
        // about sleep it had not seen for a month, and the heaviest input in the model
        // voting favourably on nothing at all. Worth 8.4 points, always toward "nothing to
        // see". Not knowing has to look like not knowing.
        let recent = all.suffix(recencyNights).compactMap { $0 }
        guard recent.count >= 1 else { return nil }
        let debt = SleepDebt.of(nights: all)
        return MetricReading(kind: .sleepDebt,
                             value: debt.hours,
                             // Owing nothing is the target, for everybody.
                             baseline: 0,
                             zScore: debt.hours / SleepDebt.hoursPerDeviation,
                             // How much history stands behind it, not how far the
                             // balance looks back: those were only ever the same
                             // number by coincidence, and the window has moved.
                             // Nights actually behind this balance, not rows in the
                             // record: confidence should not outlive the data.
                             sampleCount: min(recorded.count, debt.nights))
    }

    static func assemble(series: [DailyPhysiology], acwr: Double? = nil,
                         nightScore: Double? = nil) -> AssembledDay? {
        guard let today = series.last, today.hasReadinessData else { return nil }

        var readings: [MetricReading] = []
        var trendReadings: [MetricReading] = []

        /// `values` is one entry per calendar day, oldest first, nil on a day this metric
        /// recorded nothing.
        ///
        /// Handed through with its gaps intact. It used to be compacted first: twice, in
        /// two branches, and then sliced, so "the last sixty days" and "the last seven
        /// days" were counts of *readings*. For four nights of wear a week the seven-day
        /// HRV trend spanned twelve calendar days and after a trip seventeen, which is up
        /// to eighteen points of recovery ring, on a dip that had already recovered.
        func add(_ kind: MetricKind, _ values: [Double?]) {
            // Today itself has to have recorded, or there is nothing to place.
            guard let today = values.last ?? nil, today.isFinite,
                  let result = BaselineEngine.evaluate(daily: values) else { return }
            readings.append(MetricReading(
                kind: kind, value: today, baseline: result.mean, zScore: result.zScore,
                scoringZ: kind.scoresOnTrend ? result.trendZScore : result.zScore,
                sampleCount: result.sampleCount))
            trendReadings.append(MetricReading(
                kind: kind, value: today, baseline: result.mean,
                zScore: result.trendZScore, sampleCount: result.sampleCount))
        }

        add(.hrv, series.map(\.hrvSDNN))
        add(.restingHeartRate, series.map(\.restingHeartRate))
        // The running balance, on its own absolute scale: see `debtReading`.
        if let debt = debtReading(series) {
            readings.append(debt)
            trendReadings.append(debt)
        }
        add(.respiratoryRate, series.map(\.respiratoryRate))
        add(.bloodOxygen, series.map(\.bloodOxygenPercent))

        // HealthKit stores an absolute sleeping wrist temperature, not a deviation.
        // The deviation is only meaningful against this user's own baseline.
        // Calendar days, like everything else. This was the last reading-count window in
        // the app, and it arms the harshest override in the model: sixty *readings* of
        // wrist temperature reach back 106 calendar days at four nights of wear a week, so
        // a slow seasonal drift could read as a fever against a baseline from three months
        // ago. Measured, the false-gate rate ran 4.7x to 19x the calendar-window one.
        var wristDeviation: Double?
        let wrist = series.map(\.wristTemperatureC)
        if wrist.suffix(BaselineEngine.windowDays).compactMap({ $0 }).count >= 14,
           let result = BaselineEngine.evaluate(daily: wrist),
           let current = today.wristTemperatureC {
            wristDeviation = current - result.mean
        }

        // Days that recorded something, not calendar days: the series is dense now, and
        // this number is what the coach is told and what confidence is judged against.
        let daysOfHistory = series.filter(\.hasReadinessData).count

        let trendResult = ReadinessEngine.evaluate(
            ReadinessInput(readings: trendReadings, daysOfHistory: daysOfHistory))
        let trendPresent = abs(trendResult.composite) >= 0.5

        let readiness = ReadinessEngine.evaluate(
            ReadinessInput(readings: readings,
                           wristTemperatureDeviationC: wristDeviation,
                           acwr: acwr,
                           daysOfHistory: daysOfHistory,
                           // Only used when nothing two-sided voted, and applied inside the
                           // engine so the state, the gates and the session advice are all
                           // looking at the number the ring shows.
                           nightScore: nightScore))

        return AssembledDay(date: today.date, readiness: readiness, readings: readings,
                            wristTemperatureDeviationC: wristDeviation,
                            multiDayTrendPresent: trendPresent,
                            daysOfHistory: daysOfHistory)
    }
}
