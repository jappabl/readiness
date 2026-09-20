# Recorded sleep and daily activity scores

These are descriptive app calculations. Neither estimates a diagnosis, a training safety limit, or a validated physiological strain score. Recovery and the existing strength-load ACWR engine are unchanged.

## Sleep

`SleepScore.evaluate(breakdown:durationHours:history:targetHours:calendar:)` returns duration, continuity, schedule components and their coverage. `percent` is absent when only sleep hours are available.

The estimate is:

`100 × min(hours / targetHours, 1) × recordedContinuity × scheduleAdjustment`

- Continuity uses asleep time divided by a credible in-bed interval, or continuously covered time between first and last staged sleep samples. Conflicting awake/asleep intervals, unobserved gaps, and disconnected sleep episodes do not imply perfect continuity.
- SleepAggregator retains the longest episode's observed start/end timestamps for schedule comparison. Existing duration and stage aggregation is retained.
- Schedule comparison requires seven distinct prior wake days within 28 days. It compares the current bedtime and wake time with prior recorded clock times, including midnight wrapping. The median average difference maps linearly from zero to two hours. This supplies a factor between 1.0 and 0.9. Today, future records, duplicates and older records are excluded.
- The duration target, two-hour scale, and ten-percent adjustment are product choices. They are not clinical thresholds. No ideal deep-sleep or REM fraction is invented.
- Duration-only records still display the observed hours and target coverage. This avoids representing eight hours as 100% sleep quality.

Apple documents that Watch awake samples only cover awakenings between sleep samples, so the app calls the component recorded continuity instead of claiming complete sleep efficiency for Watch-only samples. [Apple sleep-analysis documentation](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis)

CDC distinguishes sleep duration from uninterrupted, refreshing sleep and recommends regular sleep and wake times. This supports considering continuity and schedule; it does not validate the app's numeric formula. [CDC About Sleep](https://www.cdc.gov/sleep/about/)

## Daily strain

`DailyStrain.evaluate(days:on:calendar:)` selects one available current-day Health measure, in this order: active energy, exercise minutes, steps, workout energy, workout minutes. It compares that measure with the same measure on at least seven distinct observed prior days within 28 days. No in-app session count is required.

The ring is the empirical percentile with ties given their midpoint. It describes today's accumulating activity against prior daily totals. Fifty is around usual; one hundred is among the highest observed days, not maximum possible or safe exertion. Morning values generally start lower because today is incomplete.

Missing current-day data returns no result. Sparse history returns the raw activity and observed baseline-day count, without a percentile. A recorded zero returns zero and is explicitly qualified as recorded activity, not proof that a device tracked the entire day. Missing prior days are excluded rather than zero-filled. If multiple aggregates share a day, the latest update is used once.

Only one activity measure contributes. Workout energy is never added to active energy. Apple defines active energy as energy used through physical activity and exercise and describes it as a cumulative quantity. [Apple active-energy documentation](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/activeenergyburned)

Activity source, units, coverage, partial-day comparison and missing-history behavior are visible in the detail screen. The native information sheet works even without a readiness recommendation. Workout-only fallbacks are explicitly labeled.

## Integration

```swift
var sleepScore: SleepScoreResult {
    SleepScore.evaluate(
        breakdown: today'sDailyPhysiology.sleep,
        durationHours: today'sDailyPhysiology.sleepHours,
        history: priorDailyPhysiology.compactMap(\.sleep),
        targetHours: DayAssembler.sleepNeedHours
    )
}

let activity = series.map {
    DailyActivity(date: $0.date,
                  activeEnergyKcal: $0.activeEnergyKcal,
                  exerciseMinutes: $0.exerciseMinutes,
                  steps: $0.steps,
                  workoutEnergyKcal: $0.workoutEnergyKcal,
                  workoutMinutes: $0.workoutMinutes)
}
let dailyStrain = DailyStrain.evaluate(days: activity)
```

The Health boundary must preserve unavailable data as nil. Sample aggregation must not turn an empty query into a measured zero. The existing ACWR and lifting-volume features stay independent.
