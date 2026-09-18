# Readiness

Reads overnight physiology from HealthKit, computes a readiness state against your own
rolling baseline, and turns that into today's working loads — then grades the prescription
against what you actually lifted.

v0.1 per `Readiness-to-Barbell Product Spec and Roadmap.md`. Single user, local only,
no accounts, no backend, no AI layer.

## Running it

```bash
open Readiness.xcodeproj
```

Build the `Readiness` scheme to an iPhone simulator. On first launch it asks for Health
access once, seeds 180 days of synthetic history into the simulator's HealthKit store,
then reads it back through the normal HealthKit path.

Engine tests run without Xcode or a simulator:

```bash
swift test
```

## Layout

| Path | What lives there |
| --- | --- |
| `Core/Sources/ReadinessCore` | Baseline, readiness and prescription engines. Pure functions — no I/O, no HealthKit, no dates. |
| `Core/Tests` | 50 tests over those engines. |
| `App/Health` | `HealthSource` protocol, the real HealthKit reader, and the simulator seeder. |
| `App/Domain` | Composes the engines; owns app state. |
| `App/Data` | SwiftData models and the CSV export. |
| `App/Views` | Home, Explain, Log, History, Onboarding. |

The engines are a Swift package so they can be tested in milliseconds. The app target
compiles the same sources directly, so there is no cross-module linkage to maintain.

## The model

Five weighted inputs over z-scores against a 60-day personal baseline. Weights sum to 1.0,
so the composite is a plain weighted mean and every state decomposes to contributions that
sum exactly — checkable by hand on the Explain screen.

| Input | Weight | Confidence |
| --- | --- | --- |
| HRV (SDNN) | 0.40 | Moderate |
| Resting heart rate | 0.25 | Moderate |
| Sleep debt | 0.20 | Moderate |
| Respiratory rate | 0.10 | Low |
| Blood oxygen | 0.05 | Low |

Two gates sit outside the weighted sum: wrist temperature above +0.5 °C clamps the day
(binary illness flag, not a gradient), and an ACWR above 1.5 cancels an upgrade without
ever rescuing a poor morning. Individual z-scores clamp at ±3 so no single night decides
anything.

Four states, thresholded on standard deviations from your own baseline: above, at, below,
and well below. Four is what the data supports.

Readiness maps to load as a percentage internally; the *adjustment* is then rounded to the
lift's own increment, so a squat at 315 with 10 lb jumps moves to 305 or 325, never 310.
The reported percentage is what was applied after rounding, not what was intended.

`ReadinessEngine.modelVersion` is written into every stored row, so changing the weights
later can be evaluated retrospectively against the same outcomes.

## What the simulator can and cannot tell you

The seeded history proves the app works end to end. It cannot tell you whether readiness
predicts next-day performance — only your own data over a real training block can, which is
what the CSV export exists for.

## Platform constraints found the hard way

- `appleSleepingWristTemperature` is **read-only** for third-party apps. Requesting share
  authorization for it throws an uncaught Objective-C exception and terminates the app. The
  seeder writes `bodyTemperature` instead, and the reader falls back to it — which also
  covers users without a Series 8 or later watch.
- HealthKit cannot present a second authorization prompt while the first is dismissing. It
  hangs silently with no error. Read and write authorization are requested together, once.
- Spec §9.1 sets `text.tertiary` to `#A3A39D`, which is 2.30:1 on the canvas and fails the
  contrast line of the §9.7 review checklist. The two cannot both hold; the token was
  darkened to the lightest AA-passing value and de-emphasis is carried by size and weight.

## Not in v0.1

No AI or chat, accounts, sync, payments, nutrition, Tier 2 alerts, generated charts, or
non-Apple wearables. See §4.4 and §6 of the spec — each was cut for a recorded reason.
