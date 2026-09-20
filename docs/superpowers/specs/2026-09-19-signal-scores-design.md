# Signal scores: recovery, sleep and strain on absolute scales

Status: approved 2026-09-19. Supersedes `docs/briefs/signal-scores.md` for sleep and
strain, and changes the recovery ring's transfer function.

## Why

The three numbers on the home rings do not currently carry the weight the app puts on
them.

**Recovery has almost no dynamic range, and it is an arithmetic error rather than a
tuning problem.** `AppModel.recoveryPercent` computes
`Percentile.percent(fromZ: day.readiness.composite)`, which runs the composite through a
standard normal CDF as though it were a single z-score. The composite is a weighted mean
of five clamped z-scores with weights summing to 1, so its standard deviation is
`sqrt(Σw²)` at zero correlation — about 0.49 — rising to roughly 0.83 at correlation 0.6.
Simulated over 200,000 days with the shipping weights:

| input correlation | composite SD | 1st–99th percentile of composite | a day 2 SD below shows as | share of days reaching `wellBelowBaseline` (composite < −1.5) |
|---|---|---|---|---|
| 0.0 | 0.485 | −1.12 … 1.13 | 17 | 0.11 % |
| 0.3 | 0.682 | −1.58 … 1.59 | 9 | 1.36 % |
| 0.6 | 0.831 | −1.93 … 1.93 | 5 | 3.62 % |

So the ring lives between roughly 20 and 80, and `ReadinessState.wellBelowBaseline` is
reachable in practice only through the wrist-temperature gate.

**Strain is a percentile of one metric.** `DailyStrain` picks the first available of
active energy, exercise minutes, steps, workout energy, workout minutes, and compares it
against the same measure on prior days. It cannot distinguish a threshold run from a long
walk of equal calories, and it ignores both the workout records and the in-app lifting
volume the app already holds.

**Sleep cannot see most of a night.** `SleepScore` is
`duration × continuity × scheduleAdjustment` against a fixed 8-hour target. Deep and REM
are deliberately excluded, on the reasoning in `docs/briefs/signal-scores.md` that the app
should not invent ideal stage fractions. That reasoning is sound and is preserved here —
but stages can be scored against the user's *own* distribution, which invents nothing.

Meanwhile `HealthKitSource.streams` already fetches heart rate average/min/max, walking
heart rate, heart rate recovery, VO2 max, basal energy, stand minutes, distance, daylight,
caffeine, alcohol, water, and full sleep staging. Almost none of it reaches a score.

## Decisions taken

Chosen by the product owner on 2026-09-19, recorded because they constrain everything
below:

1. **Absolute scales, not percentile-of-self.** Recovery and sleep are 0–100 %, strain is
   0–21. A given physiological deviation must always produce the same number. This is
   what WHOOP does: its recovery is personal-baseline-relative underneath but maps onto a
   fixed scale, so 80 % means the same thing every day and for every person.
2. **Strain is heart-rate load plus muscular load**, which requires a new intraday heart
   rate query.
3. **Sleep scores the whole night**, with stage and dip components measured against the
   user's own distribution.
4. **One shared Insights surface** driven by a common contributor structure.

Non-goals for this spec: per-user learned weights; Oura's recovery index (needs overnight
intraday heart rate — the data becomes available with piece 2, but the contributor is not
built here); nap detection beyond what `SleepAggregator` already separates.

## The shared structure

New file `Core/Sources/ReadinessCore/SignalScore.swift`. Every engine returns this, and
the Insights screen renders exactly this and nothing else. Adding an input to an engine
must therefore surface in the UI with no view changes.

```swift
public enum SignalKind: String, Sendable, Codable, CaseIterable {
    case recovery, sleep, strain
}

/// The fixed meaning of a range on a signal's scale. Bands are part of the contract:
/// they are what makes the scale absolute rather than relative.
public enum ScoreBand: String, Sendable, Codable {
    case red, yellow, green        // recovery, sleep
    case light, moderate, hard, allOut   // strain
}

public enum ContributorState: String, Sendable, Codable {
    case optimal, fine, payAttention
}

public struct ScoreContributor: Sendable, Equatable, Codable {
    public let id: String                 // stable, for diffing and tests
    public let title: String              // "Heart rate variability"
    public let value: Double
    public let unit: String
    public let comparison: Double?        // the user's own baseline or target
    public let comparisonLabel: String?   // "your normal", "your need"
    public let state: ContributorState
    /// Points of the final score this input moved, signed. Sums (with rounding) to the
    /// distance between the score and its neutral point, which a test pins.
    public let magnitude: Double
    public let explanation: String
    public let history: [Double]          // oldest first, for the expandable chart
}

public enum ScoreCoverage: String, Sendable, Codable {
    case full                 // every input present
    case partial              // some inputs missing, score still issued
    case buildingBaseline     // not enough history to compare against
    case unavailable          // no score
}

public struct SignalScore: Sendable, Equatable, Codable {
    public let kind: SignalKind
    public let value: Double?             // nil when coverage == .unavailable
    public let band: ScoreBand?
    public let contributors: [ScoreContributor]
    public let coverage: ScoreCoverage
    public let missing: [String]          // human-readable, for the coverage note
    public let modelVersion: String
}
```

`magnitude` is the load-bearing field. It is what lets Insights sort contributors by how
much they actually mattered today rather than by a fixed order, and it is what makes the
screen honest: a contributor that moved the score by 0.3 points must not be presented with
the same weight as one that moved it by 9.

## Recovery

`ReadinessEngine` keeps its structure. Three changes.

### 1. The transfer function

```
recoveryPercent = 100 × Φ(composite / compositeScale)
compositeScale  = 0.6
```

`compositeScale` is a stated product constant, chosen from the simulation above as the
approximate composite standard deviation at realistic input correlation. It is not derived
from the user's own data — deriving it per user would make the score a percentile of self,
which decision 1 rules out.

Resulting band edges, which tests pin:

| composite | recovery % | band |
|---|---|---|
| +1.20 | 98 | green |
| +0.26 | 67 | green (edge) |
| 0.00 | 50 | yellow |
| −0.26 | 33 | red (edge) |
| −1.20 | 2 | red |

Bands follow WHOOP: green 67–100, yellow 34–66, red 0–33.

### 2. `ReadinessState` derives from the band

`ReadinessEngine.state(for:)` currently thresholds the composite at ±0.5 and ±1.5, which
is a second, independent calibration of the same quantity. Under the numbers above, ±1.5
is a 2.5-sigma event and `wellBelowBaseline` effectively never fires.

Replace with a mapping from the score, so the ring and the recommendation cannot disagree:

| recovery % | state |
|---|---|
| ≥ 67 | `aboveBaseline` |
| 34–66 | `atBaseline` |
| 15–33 | `belowBaseline` |
| < 15 | `wellBelowBaseline` |

Gates are unchanged: an acute load spike still cancels an upgrade and never rescues a poor
morning; wrist temperature at or above 0.5 °C still forces `wellBelowBaseline`.

### 3. Contributors

`sleepDebt` as a raw metric is replaced by the new sleep score's performance percentage,
which is a better-conditioned version of the same idea and is already computed. Wrist
temperature becomes a graded contributor below the gate threshold rather than only a
binary flag.

| input | weight | change |
|---|---|---|
| HRV (7-day trend) | 0.28 | weight only |
| Resting heart rate | 0.24 | weight only |
| Sleep performance | 0.24 | **new**, replaces `sleepDebt` |
| Respiratory rate | 0.10 | weight only |
| Wrist temperature | 0.08 | **new** as a graded contributor; gate retained above 0.5 °C |
| Blood oxygen | 0.06 | weight only |

Weights sum to 1.0 and are renormalised over the inputs actually present, exactly as
today, so a missing stream stops voting rather than diluting.

Yesterday's strain enters as a gate rather than a weighted contributor, alongside ACWR: a
strain in the `allOut` band caps the state at `atBaseline`. This mirrors Oura's activity
balance and the existing ACWR gate, and avoids double-counting load that already shows in
HRV and resting heart rate.

`MetricKind.sleepDebt` stays in the enum: `DayAssembler` still derives it, the coach
context reports it, and removing it is a larger change than this spec needs. It simply
stops carrying a readiness weight.

## Intraday heart rate

New file `App/Health/IntradayHeartRate.swift`. The one new HealthKit surface, and the
prerequisite for both strain and the sleep heart-rate dip.

- `HKStatisticsCollectionQuery` over `.heartRate`, `discreteAverage`, 5-minute intervals.
  288 buckets a day; 28 days is 8,064, which is an acceptable one-off and is then cached.
- Returns `[Date: Double]` keyed by bucket start, missing buckets absent rather than zero.
- Cached in the existing daily-aggregate store keyed by day, refreshed only for days not
  already complete.
- Absence must degrade, never fail: with no intraday data, strain falls back to the
  existing activity percentile and reports `coverage == .partial` with `missing` naming
  heart rate. This is the common case on iPhone-only users and must not produce an empty
  ring.

## Strain

New file `Core/Sources/ReadinessCore/StrainScore.swift`. `StrainEngine` keeps `sessionLoad`,
`acwr` and `novelty` unchanged — those feed the prescription engine and are out of scope.
`DailyStrain` is retained as the documented fallback path.

### Cardiovascular load

Banister TRIMP, which is published and testable:

```
HRmax     = 208 − 0.7 × age                    (Tanaka)
            overridden by the user's own observed maximum when higher
HRreserve = HRmax − restingHeartRate
HRr(t)    = clamp((HR(t) − restingHeartRate) / HRreserve, 0, 1)
TRIMP(t)  = minutes × HRr(t) × 0.64 × e^(k · HRr(t))
k         = 1.92 men, 1.67 women, 1.795 when biological sex is unknown
```

The coefficient is 0.64 for both sexes; only the exponent differs. This ceilings at
4.37 TRIMP/min for men and 3.40 for women, so the scale has a real top rather than an
assumed one.

Worked example, pinned as a test: one hour at HRr 0.75, male —
`60 × 0.75 × 0.64 × e^(1.92 × 0.75) = 60 × 0.75 × 0.64 × 4.2207 = 121.6 TRIMP`.

`restingHeartRate` uses the baseline from `BaselineEngine`, not the day's reading, so a
bad morning does not inflate the whole day's load. Age missing → fall back to HRmax 190
and report `coverage == .partial`.

### Muscular load

From the in-app session, so lifting is not invisible to a cardiovascular measure:

```
muscularTRIMP = hardSets × hardSetTRIMP
hardSetTRIMP  = 2.0
```

A hard set is `rir <= StrainEngine.hardSetRIRThreshold`, which already exists. The
constant is a product choice: it puts a 20-hard-set session at 40 TRIMP, comparable to
20 minutes of moderate cardio, which is the intended relative weight. It is a single named
constant so it is cheap to retune.

WHOOP splits cardiovascular and muscular load the same way and shows both; Insights does
too, as two contributors.

### The 0–21 map

```
load   = cardiovascularTRIMP + muscularTRIMP
strain = 21 × ln(1 + load / L0) / ln(1 + Lmax / L0)
L0     = 40      (curve shape)
Lmax   = 400     (the load that reads as 21)
```

Anchors, pinned as tests:

| daily load | strain | reads as |
|---|---|---|
| 0 | 0.00 | nothing recorded |
| 20 | 3.55 | a walk |
| 40 | 6.07 | an easy session |
| 121.6 | 12.23 | the worked example above — one hard hour |
| 200 | 15.69 | a long hard session |
| 300 | 18.74 | a genuinely big day |
| 400 | 21.00 | the ceiling |
| 600 | 21.00 | clamped |

Bands: light 0–9, moderate 10–13, hard 14–17, allOut 18–21.

These constants are absolute and stated, per decision 1. The known consequence is that an
untrained user will sit low for months and a trained endurance athlete will press the
ceiling. That is the accepted cost of a fixed scale and the constants are two named values.

## Sleep

Rewrite of `SleepScore`, keeping `SleepAggregator` and `SleepBreakdown` unchanged.

### Sleep need

Replaces `DayAssembler.sleepNeedHours` as the target. WHOOP's model:

```
need = baseline + outstandingDebt × repaymentFraction + strainAdjustment − napCredit
baseline           = 8.0 h            (unchanged default; the existing constant)
outstandingDebt    = Σ over the last 7 nights of max(0, need_i − slept_i), capped at 3 h
repaymentFraction  = 0.5              (a night repays half the outstanding debt, not all)
strainAdjustment   = max(0, (strain − 10) / 11) × 0.75 h
napCredit          = hours of non-primary sleep episodes on the prior day, capped at 1 h
```

`need` is clamped to 6–11 hours. The debt is computed against each night's own need, which
recurses; the implementation resolves it iteratively oldest-first over the 7-night window
with the baseline as the seed.

### The score

```
performance = min(1, asleepHours / need)
quality     = 0.85 + 0.15 × qualityFraction
sleepScore  = 100 × performance × quality
```

`quality` is bounded to [0.85, 1.0] so that duration dominates — a full night with poor
structure loses at most 15 points, and a short night cannot be rescued by good structure.
This generalises the existing `0.9 + 0.1 × schedule` factor rather than replacing the idea.

`qualityFraction` is the mean of the available components below, each in [0, 1], each
scored **against the user's own distribution over the trailing 28 nights** via the
existing `BaselineSummary`. No component invents a clinical target.

| component | measure | scored how |
|---|---|---|
| Continuity | `SleepBreakdown.recordedContinuity` | as today, used directly (already 0–1) |
| Schedule | median bed/wake clock deviation | as today, 0–2 h maps to 1–0 |
| Deep share | `deepHours / asleepHours` | z against own 28-night distribution, mapped through Φ |
| REM share | `remHours / asleepHours` | z against own 28-night distribution, mapped through Φ |
| Awakenings | `awakeHours` during the episode | z against own distribution, inverted |
| Heart rate dip | `(daytimeHR − sleepingHR) / daytimeHR` | banded per AutoSleep: ≥0.15 optimal, 0.10–0.15 normal, 0.05–0.10 low, <0.05 poor |

The heart-rate dip needs the intraday query (sleeping window average against the
non-active daytime average) and is absent until piece 2 lands; its absence drops it from
the mean rather than scoring it as zero.

A component with fewer than `BaselineSummary.minimumReadings` nights of history is
excluded from the mean and named in `missing`, so `coverage` reports the truth.

## Insights

New file `App/Views/InsightsView.swift`, replacing the `calculationInfo` sheet and the
`WhyView` branch in `SignalDetailView`.

One screen, driven entirely by `SignalScore`:

- Header: the score, its band, and the one-line coverage note when coverage is not `.full`.
- Contributors, sorted by `abs(magnitude)` descending. Each row: title, today's value with
  unit, the comparison ("your normal 61 ms"), a `RangeBar` reusing the existing component,
  the state as colour, and the signed points it moved.
- A row expands to its `history` chart and its `explanation`.
- A footer naming the model version and stating plainly that these are the app's own
  calculations, not clinical measures — carried over from the existing brief's language,
  which is already careful and already shipped.

`WhyView` stays for the recovery *recommendation* explanation, which is a different
question ("why this session") from the score breakdown ("what moved this number").

## Consumers to update

| file | change |
|---|---|
| `App/Domain/AppModel.swift` | `recoveryPercent`, `sleepScore`, `sleepPercent`, `dailyStrain`, `strainPercent` become one `signalScore(_:)` returning `SignalScore` |
| `App/Domain/DayAssembler.swift` | feeds sleep performance into the readiness input; sleep need replaces the fixed constant |
| `Core/.../RecommendationEngine.swift` | consumes `ReadinessState`, which is unchanged in shape — verify thresholds still behave |
| `Core/.../PrescriptionEngine.swift` | same |
| `Core/.../CoachContext.swift` | reports the new scores and contributors to the coach |
| `App/Views/SignalDetailView.swift` | figures come from contributors; Insights replaces the info sheet |
| `App/Views/TodayView.swift`, `TrendsView.swift` | ring values from `SignalScore` |

## Testing

TDD in `Core/Tests/ReadinessCoreTests`, red first, as the existing engines were built.
The engines are pure functions, so all of this is testable without a device.

Pinned by test, not left to inspection:

- Every band edge in every table above, at the exact boundary value.
- The recovery transfer at composite 0, ±0.26, ±1.20.
- `ReadinessState` agrees with the band at every boundary — the specific regression this
  spec exists to prevent.
- TRIMP worked example: 60 min at HRr 0.75 male = 121.6, within 0.1.
- TRIMP per-minute ceilings: 4.37 male, 3.40 female at HRr 1.0.
- The strain anchor table, each row.
- Sleep need with: no debt, capped debt, high strain, a nap, and all four at once.
- `quality` cannot lift a short night above its performance ceiling.
- A component with insufficient history is excluded from the mean and named in `missing`.
- Contributor `magnitude` values sum to the distance from the neutral point.
- Every score degrades to `.partial` or `.buildingBaseline` rather than crashing or
  reporting a confident number, for: no intraday heart rate, no age, no biological sex,
  no sleep stages, no history.

Visual verification per the house rule: screenshot the Insights screen in every coverage
state through the `--card-gallery` harness pattern rather than asserting from code.

## Sequence

1. `SignalScore` + the recovery transfer fix and state derivation — Core only, largest
   improvement per line changed, unblocks everything.
2. Intraday heart rate source — the one new HealthKit surface, serves 3 and 4.
3. Strain on TRIMP + muscular load.
4. Sleep on need + quality.
5. Insights screen — depends only on 1, so it can land any time after.
