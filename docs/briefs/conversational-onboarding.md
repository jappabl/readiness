# Brief: rebuild onboarding as one conversation with Jett

You are working in an existing iOS app. Read this whole brief before writing code.
Everything named here exists unless the brief says to create it; use the real symbols
rather than inventing parallel ones.

## The app

**Coach Jett** — a training and recovery app. It reads Apple Health, builds a personal
baseline from the user's own history, and tells them what to do today. The coach persona
is **Jett**, who the app is named after: a face, a voice, and a chat tab. The product was
renamed from "Readiness" to "Coach Jett"; the Xcode project, target, scheme and bundle id
were deliberately left alone, so paths still read `Readiness.xcodeproj` and the domain
type `ReadinessEngine` still computes a readiness score. Do not rename any of them. Repo
root contains `Readiness.xcodeproj`,
an app target under `App/`, and a Swift package `Core/` (`ReadinessCore`) holding pure,
unit-tested logic.

- Swift 6.2, Xcode 26, deployment target **iOS 17.0**
- SwiftUI, SwiftData, Swift Charts, `Canvas`, `TimelineView`
- `DESIGN.md` at the repo root is the living design system. It is binding. Read at
  minimum sections **§5 Components**, **§6 Rules**, **§7 Motion**, **§9 Voice**, and the
  two trailing sections "Asking about what already happened" and "Motion that replaces
  words".

## The task

Onboarding is currently nine full-screen steps with a progress bar. Replace it with **a
single scrolling conversation between the user and Jett**, end to end. No separate step
screens. Jett asks; answer chips appear under his message; tapping one posts the user's
reply into the thread as their own message and Jett responds to it.

The goal is not decoration. It is that **by the time someone reaches the home screen they
have already had a conversation with Jett**, so the coach tab is a thing they already
know how to use rather than a feature they have to discover.

### Two decisions already made. Do not relitigate them.

1. **The conversation is scripted, not model-generated.** No API call during onboarding.
   There is no API key on the device at install time, onboarding must not depend on the
   network before the user has seen anything work, it must cost nothing per install, and
   Jett must not pretend to deliberate over an answer he already has. Write the turns as
   data.

2. **Free text appears exactly once, at the very end**, after the real Health read has
   completed. Every answer before that is a tap. The final message the user types is a
   real question answered by the real coach against their real numbers — see "The
   handoff" below.

## Current state — what to delete, what to keep

| Path | Lines | Action |
|---|---|---|
| `App/Views/OnboardingView.swift` | 308 | **Replace entirely.** Holds the nine-step `Step` enum and every step body. |
| `App/Views/OnboardingChrome.swift` | 219 | **Delete.** Holds `OnboardingScaffold`, `OnboardingStatement`, `ProgressTrack`. Verified: nothing outside `OnboardingView.swift` references any of the three, so the whole file goes with it. |
| `App/Design/OnboardingArt.swift` | ~430 | **Partially keep.** See below. |
| `App/ReadinessApp.swift` | — | `RootView` shows `OnboardingView()` above the `TabView` when `model.needsOnboarding`. Keep that structure. |

### The three existing animations

- **`ReadingArt`** — Jett's face with three gradient arcs (strain amber, recovery green,
  sleep blue) sweeping around him at different speeds and directions. **Keep it.** It
  becomes the thinking beat inside the thread while Health is being read.
- **`PrivateArt`** — three labelled source badges feeding a phone silhouette. **Delete
  it.** In a conversation Jett says this in one sentence and the picture is redundant.
- **`BaselineArt`** — a scatter of past nights with a band tightening around them.
  **Optional.** Build the thread without it first. If the "here is how I work" turn feels
  thin as pure text, inline it at a reduced height (~150pt) inside Jett's message bubble
  area. Do not keep it out of sunk cost; the real chart at the finale may make it
  redundant.

Whatever you delete, delete its registration in `Readiness.xcodeproj/project.pbxproj`
too, and remove any now-orphaned helpers rather than leaving them dead.

## Symbols you must reuse

**The whole point is that the onboarding thread is visually indistinguishable from the
coach tab.** Use these, do not reimplement them.

### `App/Coach/CoachProvider.swift`
```swift
struct CoachMessage: Identifiable, Equatable, Codable {
    enum Role: String, Codable { case user, assistant }
    let id: UUID
    let role: Role
    var text: String
    init(id: UUID = UUID(), role: Role, text: String)
}
```

### `App/Views/CoachStream.swift`
```swift
struct CoachTurnView: View { let message: CoachMessage }
```
Critical existing behaviour, preserve it: **the assistant's text is not a bubble.** It
runs full width as plain prose, first line set bigger and heavier as the answer, the rest
below it as detail. Only the *user's* message gets a coloured bubble. That one choice is
most of what separates this from a chat toy.

```swift
struct ThinkingPill: View { var label = "Thinking" }
struct CoachStepRow: View { let label: String; var isRunning = false }
struct CoachChartCard: View { let kind: MetricKind; var compact = false }
```
`CoachChartCard` reads `AppModel` from the environment, renders a self-drawing line via
`DrawingLine` with a derived narration line under it, and **renders nothing if it has
fewer than 2 values** — so it is safe to place before data exists, but you must not rely
on it appearing.

### `App/Design/`
```swift
struct JettRive: View {            // the animated face
    var size: CGFloat = 62
    var isThinking = false
    var isSpeaking = false
    var mood: Double = 1           // 0 concerned, 1 neutral, 2 pleased
}
struct JettFace: View             // static face, init JettFace(_ size: CGFloat)
struct PrimaryButton: View { let label: String; var symbol: String?; var tint: Color = Tokens.accent; var enabled = true; let action: () -> Void }
struct ListCard<Content: View>: View
```

`Tokens` (in `App/Design/Tokens.swift`) — every colour is a dynamic light/dark pair.
Never write a hex value. You need at least: `canvas`, `surface`, `surfaceSunken`,
`textPrimary`, `textSecondary`, `hairline`, `accent`, `onAccent`, `jettTint`,
`cardRadius`, `screenMargin`.

`Haptics` (in `App/Design/Haptics.swift`):
```swift
Haptics.committed()   // success notification — use when onboarding completes
Haptics.decided()     // rigid impact — use when a chip is tapped
Haptics.light()       // soft impact
Haptics.replyBegan()  // soft impact at 0.5 intensity — use when a Jett turn starts
Haptics.replyEnded()  // selection changed — use when a Jett turn finishes
Haptics.restOver()
```

### `Core/Sources/ReadinessCore/Onboarding.swift` and `HomeComposition.swift`
```swift
public enum TrainingGoal: CaseIterable { case getStronger, buildMuscle, loseFat, feelBetter }
//   .title, .symbol, .impliesLifting

public enum TrainingFrequency: CaseIterable { case rarely, few, most, daily }
//   .title ("0–2", "3–4", "5–6", "Every day"), .detail, .symbol, .sessionsPerWeek

public enum Obstacle: CaseIterable { case consistency, sleep, stress, nutrition, soreness, time }
//   .title, .symbol

public struct OnboardingAnswers: Sendable, Codable, Equatable {
    public var goal: TrainingGoal?
    public var frequency: TrainingFrequency?
    public var obstacles: Set<Obstacle> = []
    public var unitsAreMetric = false
    public var isComplete: Bool   // goal != nil && frequency != nil
}
```
All three enums already carry display strings. `Obstacle.title` gives "Staying
consistent", "Not sleeping enough", "Stress", "Eating well", "Soreness and niggles",
"Not enough time". Use them; do not write parallel copies in the view.

### `App/Domain/AppModel.swift`
```swift
func completeOnboarding(_ answers: OnboardingAnswers, in context: ModelContext)
func finishOnboarding()          // sets onboardingFinished; call AFTER the reveal
func refresh() async
func startBackgroundDelivery()
var needsOnboarding: Bool        // goal == nil || !onboardingFinished
var day: DayReading?             // nil until refresh() completes
var series: [DayReading]
var healthKit: HealthKitSource
```
`App/Health/HealthKitSource.swift`:
```swift
func requestAuthorization() async throws
```
Note the existing comment there: HealthKit **cannot present a second prompt while the
first is dismissing — it hangs** — so read and write are requested together or not at
all. Do not add a second authorization call.

## The conversation

Write the script as data (an array of turns or a small state machine), not as a pile of
`if` statements in a view body. Keep the copy in one place so it can be edited without
touching layout.

**Voice rules, from `DESIGN.md` §9, are binding:**
- Contractions, plain words, second person. "You're flat today", never "Your readiness is
  reduced."
- **No em dashes anywhere.**
- Banned openers: "Based on your data", "It looks like", "I'd recommend", "It's important
  to", "Great question".
- Never explain the mechanism unasked, never recap the question, never summarise at the
  end.
- He can be blunt. He is never chirpy. No exclamation marks.

### Shape of the thread

Opening (no question yet):
> **Jett:** I'm Jett. I'll read what your body is already recording and tell you what to
> do with it.

**1. Goal** — single select, chips from `TrainingGoal.allCases` using `.title`.
> **Jett:** What are you here for?

Acknowledgement must be specific to the answer, one line, and must say what changes
because of it. For `.getStronger`: "Then loads get set against how recovered you are, not
against a calendar." Write one for each of the four.

**2. Frequency** — single select, `TrainingFrequency.allCases` using `.title`; show
`.detail` as secondary text on the chip if it fits.
> **Jett:** How many days a week do you train?

Acknowledgement per case. For `.few`: "That's enough for a pattern to show up."

**3. Obstacles** — **multi select**, `Obstacle.allCases`. Needs a confirm affordance
since tapping is not terminal; a "Done" chip that is enabled with zero selections and
reads "Skip" when nothing is picked.
> **Jett:** Anything getting in the way? Pick any that apply.

Acknowledgement: "Noted. I'll keep those in mind, and I won't score you on them."

**4. Units** — single select, Pounds / Kilos → `answers.unitsAreMetric`.
> **Jett:** Pounds or kilos?

**5. How he works, then the ask.** Two assistant turns, then a button rather than chips.
> **Jett:** Here's how I work. I don't compare you to an average. I build your normal
> from your own nights, then today gets measured against that.
>
> **Jett:** I need read access to Health. Nothing leaves this phone.

The action is a `PrimaryButton` labelled "Connect Health" placed in the thread where the
chips would be. On tap call `model.healthKit.requestAuthorization()`.

**6. The read.** After the system sheet dismisses, post a `ThinkingPill` and a short run
of `CoachStepRow`s ("Reading sleep", "Reading heart rate", "Building your baselines")
with `ReadingArt` as the visual. Run `await model.refresh()` and
`model.startBackgroundDelivery()` behind it.

**Hold this state for a minimum of 1.3 seconds even if the read finishes instantly.**
This is already solved in the current code and you should copy the technique: measure
with `ContinuousClock`, sleep only the remainder. The read is often faster than one
frame; without the floor this state never renders and reads as a stutter. See the commit
"Hold the reading step long enough to be a step".

**7. The reveal.** Jett posts the real result. Use `CoachChartCard` with real data, not a
fabricated illustration. The headline states the actual count of days read.
> **Jett:** 179 nights, read. That's your normal now, and I'll tell you when it moves.

**8. The handoff.** Jett invites a question and the composer appears for the first time.
> **Jett:** Ask me anything about it.

## The handoff (important, get this right)

The composer at the end must be the **real** thing, not a mock. Look at
`App/Views/CoachView.swift` lines ~263-300 for the existing composer: a `TextField` with
`axis: .vertical`, `lineLimit(1...4)`, a circular send button that is disabled when empty
or streaming. Match it exactly.

On send:
1. `model.completeOnboarding(answers, in: context)`
2. `model.finishOnboarding()`
3. Dismiss onboarding and land on the **coach tab**, with the user's typed message
   already in the thread and a real request in flight against it.

Step 3 needs plumbing that does not exist yet. `RootView` in `App/ReadinessApp.swift`
owns the selected tab. Add a seed path: something like an optional pending message on
`AppModel` that `CoachView` picks up in `.task` and sends once, then clears. Keep it
small and one-shot; do not build a general message queue.

If the coach is not configured (no API key) the request will fail with
`CoachError.notConfigured`. **That is an acceptable outcome and must not look broken** —
the existing `CoachView` already renders coach errors; make sure the seeded path goes
through the same error rendering rather than a new one.

## Edge cases you must handle

- **Health declined.** `requestAuthorization()` does not throw when the user denies; the
  read simply returns nothing. Jett must still say something true and move on, and
  onboarding must still complete. Do not block the user in the thread.
- **No data even after granting.** A brand new phone with no history. `model.day` is nil
  and `CoachChartCard` renders nothing. Jett needs a turn for this case: say plainly that
  there is not enough history yet and what will happen as it accumulates.
- **Changing the last answer.** A thread has no back button. Make the user's most recent
  message bubble tappable: tapping it removes Jett's follow-up and restores that
  question's chips. Only the most recent one. Do not build general editing.
- **Reduce Motion.** `@Environment(\.accessibilityReduceMotion)`. Typing delays and
  scroll animations collapse; the thread still works.
- **Dynamic Type.** Chips must wrap rather than truncate. Test at the largest
  accessibility size.
- **VoiceOver.** Each turn is one element. Jett's messages need a speaker prefix the way
  `CoachTurnView` already labels user messages ("You: ..."). Chips are buttons with clear
  labels.
- **Dark mode.** Everything comes from `Tokens`, so this should be free. Verify it anyway;
  a recent bug had a translucent accent wash that looked calm on light and radioactive on
  dark.

## Pacing

Jett's turns should appear with a short delay so it reads as a person typing, **not** as a
fake loading state. 300 to 600 ms between his consecutive messages. `Haptics.replyBegan()`
when a turn starts appearing, `Haptics.replyEnded()` when it lands, `Haptics.decided()` on
a chip tap. The only place a real `ThinkingPill` belongs is step 6, where something
genuinely is being computed.

Auto-scroll to the newest turn using `ScrollViewReader` + `proxy.scrollTo(id, anchor:
.bottom)`; `CoachView` already does this around line 199, copy the approach.

No progress bar. Four questions is short enough that a progress indicator would be chrome.

## Project mechanics

`Readiness.xcodeproj/project.pbxproj` is **hand-maintained**. Every new Swift file needs
four edits, all of them:
1. A `PBXBuildFile` entry
2. A `PBXFileReference` entry
3. An entry in the enclosing group's `children`
4. An entry in the target's `Sources` build phase `files`

Use a fresh 24-character uppercase hex id for each of the two new object ids. Assert your
edit count after patching; a partial registration compiles locally and fails in CI.

Build:
```
xcodebuild -project Readiness.xcodeproj -scheme Readiness \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug build
```

Core tests (248 currently passing, keep them green):
```
swift test --package-path Core
```

Any logic worth a branch belongs in `Core/Sources/ReadinessCore/` with swift-testing tests
(`@Test`, `#expect`, `@Suite`) written **before** the implementation. The script's
sequencing — which question comes next given the answers so far — is exactly this kind of
logic. Views should be thin.

## Verification — not optional

This repo's rule is that **you look at the rendered UI before claiming it works.** Reading
the code is not verification. In one recent session this discipline caught six real bugs
that were invisible in source, including a scatter plot whose sample mean was off-centre
so the picture contradicted the sentence under it.

Run a fresh install and walk the whole thread on the simulator:
```
xcrun simctl uninstall booted com.readiness.barbell
xcrun simctl privacy booted reset health com.readiness.barbell
xcrun simctl install booted <path to Readiness.app>
xcrun simctl launch booted com.readiness.barbell
xcrun simctl io booted screenshot /tmp/shot.png
```
Screenshot every state: each question, the multi-select with two picked, the permission
button, the reading beat, the reveal, the composer. Then repeat in dark mode
(`xcrun simctl ui booted appearance dark`). Note that `simctl io screenshot` lags the
device by roughly a second, so transient states need a delayed capture loop rather than a
single shot.

## What not to do

- Do not call an LLM during onboarding.
- Do not invent a second chat component. If `CoachTurnView` needs a change to serve both
  places, change it, and keep the coach tab working.
- Do not give the assistant's text a bubble.
- Do not add a progress bar, a skip-all button, or a "welcome to Coach Jett" splash.
- Do not use em dashes in any user-facing string.
- Do not fabricate numbers in the reveal. If the data is not there, say so.
- Do not leave `OnboardingChrome.swift` in place "just in case" if nothing references it.

## Deliverables

1. The rebuilt flow, building clean, with `swift test --package-path Core` green.
2. Tests in `ReadinessCore` for the script's sequencing and for `OnboardingAnswers`
   completeness.
3. Screenshots of every state, light and dark.
4. A short note listing: which files you deleted, what you added to `AppModel` for the
   handoff, and anything in this brief you deliberately did not do, with the reason.
