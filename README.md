# Readiness

A health dashboard that understands lifting, with an evidence-grounded coach on top.
Reads overnight physiology from HealthKit, turns it into a training decision — Push,
Maintain, Reduce, Recover — and proposes the smallest concrete change to today's session.

The point is that you leave with a decision, not another score.

## Running it

```bash
open Readiness.xcodeproj
```

Build the `Readiness` scheme to an iPhone simulator. On first launch it asks for Health
access once, seeds 180 days of synthetic history into the simulator's HealthKit store,
then reads it back through the normal HealthKit path.

Engine tests need no Xcode and no simulator:

```bash
swift test
```

The coach needs your own Anthropic API key, entered in Profile and stored in the
Keychain. Everything else works without it.

## Layout

| Path | What lives there |
| --- | --- |
| `Core/Sources/ReadinessCore` | Baselines, readiness, strength load, the decision layer, session planning, insights, and the coach context. Pure functions — no I/O, no HealthKit, no dates. |
| `Core/Tests` | 118 tests over those engines. |
| `App/Health` | `HealthSource` protocol, the real HealthKit reader, the simulator seeder. |
| `App/Domain` | Composes the engines, owns app state, holds all user-facing copy. |
| `App/Data` | SwiftData models. |
| `App/Coach` | Provider protocol and the Claude implementation. |
| `App/Views` | Today, Train, Coach, Trends, Profile. |

The engines are a Swift package so they test in milliseconds. The app target compiles the
same sources directly, so there is no cross-module linkage to maintain.

## How a decision gets made

1. **Normalize.** Each metric against that user's own 60-day rolling baseline, as a z-score.
2. **Derive.** Weighted composite, plus strength load: hard sets per muscle group, volume
   load excluding warm-ups, proximity to failure, ACWR, novelty.
3. **Decide.** A deterministic layer maps composite + gates + check-in to a training state
   and a set of concrete adjustments.
4. **Explain.** The language model explains and personalises that decision. It never
   computes it, and it is one replaceable part behind a protocol.
5. **Record.** The recommendation, the user's response, and the session that followed.

### The weights

| Input | Weight | Confidence |
| --- | --- | --- |
| HRV (SDNN) | 0.40 | Moderate |
| Resting heart rate | 0.25 | Moderate |
| Sleep debt | 0.20 | Moderate |
| Respiratory rate | 0.10 | Low |
| Blood oxygen | 0.05 | Low |

They sum to 1.0, so the composite is a plain weighted mean and every state decomposes into
contributions that sum exactly — checkable by hand on the Why screen.

Outside the weighted sum: wrist temperature above +0.5 °C clamps the day as a binary
illness flag, ACWR above 1.5 cancels an upgrade without ever rescuing a bad day, and
individual z-scores clamp at ±3 so no single night decides anything. The morning check-in
shifts the composite by at most 0.5 SD — a perfect self-report cannot override a genuinely
bad morning, which is the entire reason to measure.

Load adjustments round to the lifter's own loadable grid: a squat at 315 with 10 lb jumps
moves to 305 or 325, never 310. `ReadinessEngine.modelVersion` is written into every stored
row so changing the weights later can be evaluated against the same outcomes.

## What leaves the device

Only a derived summary, and only when you use the coach: today's state, each metric's
value, baseline and z-score, your check-in, your program, and up to 14 days of prior
states. Rounded, capped, and asserted by test to contain no raw sample or timeseries
field. Nothing is sent for advertising or analytics, ever.

## What the simulator can and cannot tell you

The seeded history proves the app works end to end. It cannot tell you whether readiness
predicts next-day performance — only real data over a real training block can.

## Platform constraints found the hard way

- `appleSleepingWristTemperature` is **read-only** for third-party apps. Requesting share
  authorization throws an uncaught Objective-C exception and terminates the app. The seeder
  writes `bodyTemperature` instead and the reader falls back to it, which also covers users
  without a Series 8 or later watch.
- HealthKit cannot present a second authorization prompt while the first is dismissing. It
  hangs silently with no error. Read and write are requested together, once.
- A safety refusal from the Messages API arrives as HTTP 200 with `stop_reason: "refusal"`,
  so it has to be read off the stream rather than caught as an error.

## Design decisions worth knowing

- The recommendation is the dominant element on Today; the three signals support it. The
  scores are named Readiness / Sleep / Load and are deliberately not presented as a
  coequal recovery/strain/sleep triad.
- No colour encodes the recommendation. Colour appears only on trend direction, where it
  carries meaning that text also carries.
- Every token pair passes WCAG AA at 4.5:1 in both light and dark. The spec's
  `text.tertiary` value did not, and was darkened.

## Not in v1

No social feed, nutrition logging, Android, non-Apple wearables, video exercise
recognition, autonomous plan generation, or a general-purpose assistant. No medical
diagnosis, injury prediction, or treatment claims — the coach stops and refers out.
