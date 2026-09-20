# When Jett speaks: notifications and the ambient channel

Status: approved 2026-09-19. First notification strategy for the app. Adds a widget
extension target and a notification decision engine in `ReadinessCore`.

## Why

The app currently sends exactly one notification, from `GymPresence.offerToLog`
(`App/Health/GymPresence.swift:160`), and has no strategy behind it: no scheduling, no
budget, no quiet hours, no categories or actions, no permission flow beyond an inline
`requestAuthorization` at the moment of firing, and no tests.

The obvious answer — a morning notification carrying the recovery score, every day, the
way WHOOP and Oura do it — fails the app's own house rules. "Your recovery is 71" on a
morning the user already knows they slept badly is showing somebody what they already
know. A notification that fires regardless of whether anything happened is the single
most reliable way to train a user to swipe without reading, and once that habit exists
the one morning the app has something urgent to say is the morning it gets ignored.

`InsightEngine` already states the principle in its own header: *"a feed of generic
observations is worse than silence, because it teaches the user to stop reading."* This
spec extends that from insights to every channel the app can reach out on.

## The governing rule

**The app interrupts when it knows something the user does not, that changes what they
do today.**

Everything below is derived from that sentence. Where a candidate moment fails it, the
moment is either moved to the ambient channel or dropped.

## Decisions taken

Chosen by the product owner on 2026-09-19, recorded because they constrain everything
below:

1. **Two channels with opposite frequency budgets.** Acknowledgment ("nice nap", "good
   start to your day") and information ("your temperature is up") are different jobs and
   must not share a pipe. Acknowledgment goes to a widget, which is free and never
   interrupts. Information goes to a push notification, which is expensive and rare.
2. **The widget ships in this pass**, as a family of three kinds.
3. **The morning verdict is not rate-limited. Everything else is.** The app's core
   output is not an extra and must not compete with extras for a budget. The optional
   moments run through a token bucket, so several in one day are permitted when the day
   earns them and habitual chattiness is not.
4. **No `com.apple.developer.usernotifications.time-sensitive` entitlement.** Nothing
   this app knows decays in minutes.
5. **Notification copy is deterministic template, never the Claude proxy.**
6. **The promise made at permission time states no number.** A stated frequency is a
   contract the system then owes the user.

Non-goals, with reasons, in "What this spec refuses" below.

## The two channels

| | Widget | Push notification |
|---|---|---|
| Job | Acknowledgment. Jett being present. | Information. Something changed. |
| Seen | ~90 times a day, when the user looks | On the lock screen, unbidden |
| Frequency | Every refresh. Always says something. | Rare, budgeted |
| Cost of a weak message | ~zero | Erodes the channel permanently |
| Threshold to speak | `SignalScore.notableMagnitude` (2.0) | A higher bar — see "Two bars, one engine" |

The widget is load-bearing for this design. Without an ambient channel, every warm or
low-stakes thing the app wants to say has nowhere to go but the lock screen, and the
pressure to over-notify returns. It is not an enhancement bolted on afterwards; it is
what makes the notification budget affordable.

## The moments

| | Moment | Trigger | Spends a coin |
|---|---|---|---|
| A | Morning verdict | Overnight data lands, user has woken | no |
| B | Illness gate | `ReadinessGate.elevatedWristTemperature` fires | no |
| C | Gym arrival | `GymDetector.shouldOfferLogging` (exists) | no |
| D | A new insight | `InsightEngine` returns a finding not sent before | yes |
| E | Bedtime target | Approaching usual bedtime, tonight is unusual | yes |

### A — Morning verdict

Fires when the sleep data for the wake day has landed and local time is ≥ 06:00. At
most once a day. **Not budgeted** — see "The speaking budget" for why.

`SignalScore.summary` already produces the sentence this needs: it names the contributor
that actually moved the number, with the measurement and the comparison, and it refuses
to speak when nothing moved ("Nothing stood out today"). It is generic over the three
signals, so a new input starts appearing in notifications the day it starts counting,
with nobody editing a template.

One gate on top of it: **a higher magnitude bar than the screen uses.**
`notableMagnitude = 2.0` is tuned for text sitting next to the number, where the reader
has already chosen to look. A lock screen should cost more. Push requires the leading
contributor to have moved the score by at least `notableForInterruption` points (starting
value: 5.0, a new constant).

That is the only gate. `summary` returning "Nothing stood out today" is what produces
silence; an unremarkable night gets no push and the widget carries it. On a typical person
this fires three or four mornings a week, and seven during a bad fortnight — which is
correct.

**Direction:** A fires on bad nights, and on exceptional good ones (near a personal best,
rare by construction). Not on ordinary good nights. Warmth is the widget's job, where it
is free and seen constantly. Jett is therefore not a coach who only appears to criticise:
he is warm where it is cheap and interrupts only where it costs something.

**A novelty rule was considered and rejected.** Suppressing a morning because its leading
contributor matches yesterday's would silence the fifth consecutive rough night, which is
a fifth day the user should train differently. The measurements differ night to night even
when the contributor does not. Novelty is kept for moment D, where the finding genuinely
is the same fact restated.

The check-in is attached to this notification as a `UNNotificationAction`, not sent as
its own notification. A check-in nudge is the app asking the user for a favour on exactly
the days it has nothing else to say, which is the worst possible correlation.

Interruption level: `.passive`.

### B — Illness gate

Fires when `ReadinessResult.gateApplied == .elevatedWristTemperature`. This is the one
thing the app plausibly knows before the user does — wrist temperature elevation often
precedes felt symptoms — and training hard into an illness is the concrete harm the app
exists to prevent. Exempt from the budget: it must never be crowded out.

Still delivered at wake, not at 03:00. Interruption level `.active` (default): it appears
on the lock screen with sound and respects Focus. It does not deserve `.timeSensitive` —
the message is "don't train hard today", the user has hours, and claiming an entitlement
for something that does not decay in minutes is a poor argument to make to App Review.

### C — Gym arrival

Exists. Transactional rather than editorial: it responds to something the user just did,
like a delivery notification, so it does not spend from the same budget as the messages
Jett initiates. Three defects to fix while we are here — see "Prerequisites and defects".

### D — A new insight

Fires when `InsightEngine` produces a finding whose text differs from the last one sent.
`InsightEngine.sleepPerformancePattern` returns nil unless there are at least six
sessions and a lift of at least 10 %, so this is expected to fire roughly monthly, or
never. That low frequency is the feature: it is the only channel in the app carrying a
fact the user genuinely could not have worked out themselves.

Interruption level: `.passive`.

### E — Bedtime target

Fires in the window approaching the user's usual bedtime.

This is the only moment where the app changes an outcome rather than reporting one. Every
other message describes data already fixed — the morning verdict is about a night that
cannot be altered. A bedtime target is actionable at the instant it arrives.

Everything needed already exists: `SleepNeed.of(priorNights:strain:napHours:)` computes
tonight's need as baseline + partial debt repayment + today's strain adjustment, and
`SleepScore` derives the usual bedtime from `primarySleepStart` history
(`Core/Sources/ReadinessCore/SleepScore.swift:472`).

Gated on tonight being **unusual for this user** — a meaningfully raised need, driven by
a hard day or accumulated debt. On an ordinary night the widget carries it silently. The
days that produce two messages are therefore exactly the days that earned two: you
trained hard, so you got a morning verdict and an evening target.

Interruption level: `.passive`.

## The speaking budget

**The budget governs the optional moments only — D and E. Moments A, B and C are
outside it.**

This is the correction to an earlier draft, and the reasoning matters enough to record.
Putting the morning verdict in a budget treats "how did I sleep" as one of several
nice-to-haves competing for an allowance. It is not an extra; it is what the user opened
an account for. Two supporting arguments:

- **"They already know they slept badly" is often false.** A five-hour night is felt. A
  seven-hour night with almost no deep sleep, four awakenings and a sleeping heart rate
  six beats high is not — that night felt fine. It is precisely the case the app exists
  to catch, and a budget would have silenced it on the days a bad stretch made it most
  worth saying.
- **The failure modes are not symmetric.** Too loud is visible and self-correcting: the
  user mutes the app or complains. Too quiet is invisible — they never learn what they
  were not told. That asymmetry should bias the core message toward speaking.

For D and E: a token bucket, reusing `BurstLimiter`
(`Core/Sources/ReadinessCore/BurstLimiter.swift`) with different constants. Its existing
contract is exactly the one wanted here: *"never refuses somebody twice for the same
reason: waiting always earns the next one back."*

- **Capacity: 3.** How many optional messages can go out close together on one eventful
  day.
- **Refill: one per 48 hours.** Sets the long-run average, around 3–4 a week on top of
  whatever the morning verdict is doing.

A weekly counter was considered and rejected: it cannot distinguish four messages spread
across a week from four on Monday, and it resets on an arbitrary boundary, so a user who
spends the allowance by Saturday is mute until midnight Sunday and then has a full
allowance again. The bucket has no boundary — it simply makes a busy day cost something.

Only D and E draw from the bucket. A, B and C are exempt.

Tuning, if it is wrong in practice: lengthen the refill for a quieter app (72 h → ~2.3 a
week), shorten it for a chattier one (36 h → ~4.7 a week). Capacity changes burstiness
only, not the average.

`BurstLimiter` is not modified and not generalised. It guards a paying user's
conversation with the coach, and no notification change should be able to reach it. The
notification budget is its own type with the same arithmetic and its own constants —
about twenty-five lines of deliberate duplication, which is the cheaper risk. The
backwards-clock guard is duplicated too, and is pinned by its own test so the two cannot
drift silently.

## Timing

**Wake-triggered, not clock-scheduled.** A morning notification fixed to 07:00 is why
health apps ping people at seven on a Sunday. The app can see when the sleep episode
ended, so the morning verdict is held until (a) the overnight data has landed and (b)
local time is ≥ 06:00. Where wake is not detectable, fall back to a user-set time.

HealthKit background delivery is already wired
(`AppModel.startBackgroundDelivery`, `App/Domain/AppModel.swift:302`) and already
observes `.sleepAnalysis` at `.hourly` frequency
(`App/Health/HealthKitSource.swift:526`), so the morning message can land within about an
hour of waking rather than at a guessed time.

**Quiet hours are not `Nightfall`.** `Nightfall` (21:00–06:00) is a *display* preference
governing which scheme the app wears. Quiet hours are a *delivery* contract. They will
diverge — somebody working nights wants a dark interface at 14:00 and silence at 10:00 —
and coupling them would make one unfixable without breaking the other. Notification
quiet hours are their own stored preference, defaulting to the same window.

## Voice

**Deterministic templates in Jett's voice, defined in Core beside the engine. Never the
proxy.**

The strings live in `ReadinessCore` rather than `App/Domain/Copy.swift` because the
engine must be provable by `swift test`, and an App file is unreachable from there. Core
already owns user-facing prose (`SignalScore.summary`, `ReadinessGate.explanation`), so
the rule `Copy.swift` exists to enforce — one voice, kept together, never scattered
through views — is preserved rather than broken. `Copy.swift` remains for view copy.

Four reasons, in order of weight:

1. A notification fires from the background at a time-critical moment. A network call
   there can fail, hang, or be slow; a template cannot.
2. It would be the only Jett surface an unentitled user touches. Either free users get
   model-written copy for free, or they get a visibly worse notification. Both are bad.
3. It is the highest-risk string in the app: no surrounding context, no chance for the
   user to push back, read on a lock screen in three seconds. That is the worst place to
   put an unsupervised model and the least place it adds.
4. `Copy.swift` already exists for exactly this — *"every user-facing string that
   describes a decision, kept together so the product's voice is one thing"* — and
   `SignalScore.summary` already generates the sentence, generically and under test.

**Where the model does earn its place: tapping the notification opens Jett with the
moment's context preloaded.** The notification is a doorway, not a broadcast. That
conversation is foreground, entitled, and cost-bounded.

### Two bars, one engine

The same `SignalScore.summary` sentence serves both channels at different thresholds:

- Widget speaks at `notableMagnitude` (2.0) — the reader chose to look.
- Push speaks at `notableForInterruption` (5.0) — the app chose to interrupt.

One engine, two bars. Adding a third channel later means adding a constant, not a
template.

### The widget's line always says something

A widget is a fixed frame handed over by the OS, so "hug the content" cannot apply to it;
a blank line is literally the half-empty box that rule forbids. On a day with nothing to
report the line says something small and true — *"Quiet night. Nothing to flag."* This is
affordable precisely because it is the free channel, and it is what the Jett-solo widget
needs most, since the line is all it has.

## Permission

Asked once, at the end of onboarding, with the reason on screen and in Jett's voice:

> "I'll be a good coach and tell you when something's up. I won't be annoying about it,
> promise."

**No number.** A stated frequency turns a character trait into a contract: the first week
the app sends one more than it promised, Jett is a liar. It is also the app discussing its
own mechanics at the exact moment it is establishing that it is not that kind of app.

This follows the pattern `GymPresence` already uses carefully for location
(`resumeIfAuthorised`, `App/Health/GymPresence.swift:75`): never prompt for something
nobody asked for, because a permission dialog nobody asked for is a permission denied
forever. The current notification ask violates that pattern; see below.

## When there is no data

**Silence, always.** No "we couldn't read your data", no "connect your watch", no
re-engagement of any kind. If there is no score, the app has nothing to say, and saying so
is the app talking about itself. A broken pipe is surfaced inside the app, where
`AppModel.healthReadError` already lives.

## The widget family

Three kinds. Configurable rather than duplicated, so the gallery does not show five
near-identical tiles.

| Kind | Sizes | Contents |
|---|---|---|
| **Today** | small · medium | small: recovery ring alone. medium: three rings + Jett's line |
| **Signal** | small | One ring, which signal chosen via `AppIntentConfiguration` |
| **Jett** | small · medium | The line alone, no rings |

`Signal` uses `AppIntentConfiguration` so one gallery entry covers recovery, sleep and
strain — the iOS 17 pattern, and it gives "each ring separately" without three entries.

Data reaches the widget through an **App Group** container: `AppModel.refresh()` writes a
small `Codable` snapshot (three scores, the line, a timestamp), and the widget reads it.
The widget does not query HealthKit or SwiftData itself.

Verification surface, per house rule 10: 7 renderings × light/dark × 4 data states (full,
partial, building baseline, unavailable) ≈ 56 screenshots. This is most of the widget
work and should be budgeted as such.

## Architecture

**Core (`ReadinessCore`) — pure, TDD'd, no iOS API surface:**

- The decision: given today's scores, yesterday's sent-message record, the bucket state
  and the clock, should the app speak, which moment is it, and what is the sentence?
- The budget arithmetic.
- The novelty comparison, for moment D only.
- The bedtime-unusual gate.

**App — delivery only:**

- `UNUserNotificationCenter` wiring, categories, actions.
- The permission flow at the end of onboarding.
- Wake detection and the hold-until-06:00 logic.
- The App Group snapshot write.

The split matters because the product decisions in this document are all in the first
list. They should be expressible, and provable, without a simulator.

## Testing

Core gets tests first, per the repo's practice (455 tests via `swift test`). The cases
that must exist before implementation:

- A morning that repeats yesterday's leading contributor **does** speak — the novelty
  rule does not apply to A.
- A morning below `notableForInterruption` but above `notableMagnitude` reaches the
  widget and not the push.
- A morning whose `summary` is "Nothing stood out today" produces no push.
- An ordinary good night produces no push; a near-personal-best does.
- An empty bucket suppresses D and E, and does not suppress A, B or C.
- Two eligible mornings on the same calendar day produce one push.
- The bucket refills across a clock change, including backwards (`BurstLimiter` already
  handles this; the notification budget must not lose it).
- An ordinary night produces no bedtime message; a high-strain day does.
- `.unavailable` coverage produces no morning verdict, illness gate, or bedtime target —
  the three moments that read today's scores to say something about today. A new
  insight is exempt: it is derived from session history rather than today's data, so it
  stays true, and worth sending, on a day the watch was not worn.
- The gate produces a notification even when the bucket is empty and even when the
  morning verdict was suppressed for being unremarkable.

App-side verification is by screenshot per house rule 10, using launch-argument
harnesses in the style of `--demo-today`, `--insights`, `--signal`, `--card-gallery`
rather than tapping through the simulator.

## Prerequisites and defects

### Prerequisite: naps inflate last night's sleep score

**This must be fixed before either channel quotes a sleep number**, or the widget and the
notification will disagree about the same night.

`SleepAggregator.byWakeDay` buckets every sleep episode by the day the user woke up on. A
nap at 15:00 Tuesday and the sleep ending 07:00 Tuesday land in the same bucket, and
`Core/Sources/ReadinessCore/SleepAggregator.swift:108` does
`breakdown.asleepHours += episodeHours`, summing them. That flows through
`SleepBreakdown.recordedSleepHours` → `App/Health/HealthKitSource.swift:203` →
`durationHours` in `AppModel.sleepScore`, which is the numerator of the sleep headline.

Net effect: **last night's sleep score rises in the afternoon if the user naps.** Second
symptom in the same loop — `SleepAggregator.swift:100` nils `recordedContinuity` for any
second episode, so a nap also erases last night's continuity reading.

Separately, `SleepInput.napHours` is only ever supplied in tests. Both production call
sites (`App/Domain/AppModel.swift:529`, `App/ReadinessApp.swift:255`) omit it, so nap
credit against tonight's need is always zero.

Fixed on its own branch, not inside this work.

### Defects in the existing gym notification

1. **The permission ask cannot succeed.** `GymPresence.offerToLog`
   (`App/Health/GymPresence.swift:162`) calls `requestAuthorization` from a background
   location callback. The system alert cannot be presented while the app is backgrounded,
   so the first gym arrival produces no notification and the user never learns they were
   asked. Moving the ask to the end of onboarding, as specified above, resolves this.
2. **`UIBackgroundModes: processing` is dead.** `App/Info.plist` declares it, but there
   is no `BGTaskSchedulerPermittedIdentifiers` key and no `BGTaskScheduler` registration
   anywhere in the app. Either wire it or remove the declaration.
3. **No category or actions.** The body says "Tell me what you're lifting and I'll log
   it" and tapping it opens Today. It should open logging.

## What this spec refuses

Each of these was considered and rejected; recorded so they are not re-proposed.

- **An unconditional morning score notification.** "Your recovery is 71", every morning,
  whether or not anything happened. Note the distinction from moment A, which can also
  fire seven days in a row: A fires because the night produced something worth saying and
  goes quiet when it did not. What is refused is the *unconditional* version — firing on
  a schedule rather than on a finding, and leading with the number the widget already
  shows rather than the sentence explaining it.
- **Streaks.** An engagement metric wearing the costume of the user's progress. For a
  recovery app it is actively harmful: "don't break your 12-day streak" on a morning the
  app is saying recover is the app arguing with itself in front of the user.
- **Weekly summaries.** The failure is the *weekly* part — firing on a calendar boundary
  whether or not the week contained anything. The salvageable version is moment D, which
  fires when an insight exists rather than when a week ends.
- **A check-in nudge.** The check-in is an input worth at most 0.5 SD
  (`RecommendationEngine.maximumCheckInShift`), and nudging for it means asking the user
  for a favour on the days the app has nothing to offer. It becomes a notification action
  on moment A instead.
- **A badge.** An unread count over content that has no unread state, and the cheapest
  possible way to teach somebody to ignore a red dot.
- **Live Activities.** No ongoing activity with live-changing state. Revisit if
  in-progress workouts become a feature.
- **Lock-screen accessory widgets.** Monochrome-vibrant rendering is a separate design
  problem and roughly doubles the verification surface for little gain this pass.
- **The time-sensitive entitlement.** See moment B.
- **Model-written notification copy.** See "Voice".
- **A notification-frequency preference.** Not yet. A preference set during onboarding is
  aspirational — nobody knows on day one how a daily message feels in week six, so the
  answer collected is a guess that then has to be honoured as a mandate. The product
  owner is the first user and has already stated the default (tell me when the night was
  bad, every day). Ship that, live with it, and tune from the reaction. If people do turn
  out to differ, the control belongs on the notification itself ("less of these"), where
  the judgement is real, rather than buried in Profile.
- **Any re-engagement message.** "We haven't seen you in a while" is the app's retention
  problem presented as the user's.

## Build order

1. **The nap fix** — separate branch, ships independently.
2. **Core: the decision engine** — pure functions, TDD, no iOS surface. Nails the product
   decisions in this document in code before any plumbing exists.
3. **App: delivery** — permission flow, wake trigger, categories and actions, and the
   three gym-notification defects.
4. **Widget** — new target, App Group, the three kinds.

Each of 2–4 gets its own implementation plan.
