---
name: Coach Jett
description: Native health and training guidance, with a Messages-style coach conversation.
colors:
  message-blue: "#0074E8"
  message-on-blue: "#FFFFFF"
typography:
  conversation-body:
    fontFamily: "-apple-system"
    fontSize: "17pt"
    fontWeight: 400
  conversation-choice:
    fontFamily: "-apple-system"
    fontSize: "15pt"
    fontWeight: 500
rounded:
  message: "20pt"
  message-tail: "6pt"
  conversation-choice: "16pt"
  composer: "26pt"
spacing:
  conversation-gap: "12pt"
  conversation-margin: "16pt"
components:
  incoming-message:
    typography: "{typography.conversation-body}"
    rounded: "{rounded.message}"
    padding: "11pt 15pt"
  message-composer:
    typography: "{typography.conversation-body}"
    rounded: "{rounded.composer}"
  outgoing-message:
    backgroundColor: "{colors.message-blue}"
    textColor: "{colors.message-on-blue}"
    typography: "{typography.conversation-body}"
    rounded: "{rounded.message}"
    padding: "11pt 15pt"
  conversation-choice:
    typography: "{typography.conversation-choice}"
    rounded: "{rounded.conversation-choice}"
    padding: "13pt 14pt"
  connect-health:
    backgroundColor: "{colors.message-blue}"
    textColor: "{colors.message-on-blue}"
    height: "50pt"
---

# Design system

The spec for how this app looks and behaves. Edit this file; `App/Design/Tokens.swift`
and `App/Design/Components.swift` implement it.

The conversation frontmatter records the reusable values in `CoachStream.swift` and
`OnboardingView.swift`. Conversation font sizes are the standard-size equivalents;
SwiftUI Dynamic Type styles remain the native source of truth. UIKit resolves the
conversation's system background colors for the current appearance. Existing sections
below retain the wider app's design decisions.

---

## 1. Colour

Defined as semantic tokens, resolved per appearance. **No view hardcodes a hex.**

### Surfaces

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `canvas` | `#F1F1F4` | `#0E0E10` | Page background |
| `surface` | `#FFFFFF` | `#1C1C1F` | Cards |
| `surfaceSunken` | `#F7F7F9` | `#17171A` | Recessed areas |
| `hairline` | `#E8E8EC` | `#2A2A2E` | Dividers |

### Type

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `textPrimary` | `#1C1C1E` | `#F2F2F5` | Values, names, body |
| `textSecondary` | `#86868B` | `#98989E` | Labels, units, captions |
| `textTertiary` | `#6E6E73` | `#8A8A90` | Timestamps, metadata |

All pairs measure **≥ 4.5:1** against both `canvas` and `surface`. Re-check with the
contrast script before changing any of them.

### Conversation

`messageOutgoing` uses `colors.message-blue` with `messageOnOutgoing` white text.
This pair measures 4.503:1. Conversation actions share this blue; the app's green brand
accent remains in place on the surrounding health and training screens.
`messageCanvas` resolves `UIColor.systemBackground`; `messageIncoming` resolves
`UIColor.secondarySystemBackground`. Keep these semantic UIKit colors rather than
copying one appearance's resolved values into a view.

### Signals

Each signal owns a hue used on its ring and its detail sky. The hue says *which*
signal you are looking at — **it never encodes whether the day is good or bad.** That
is the coaching card's job, in words.

| Signal | Start (light) | Mid | Tip (deep) |
| --- | --- | --- | --- |
| Strain | `#FAD98A` | `#F0AE28` | `#CE7A17` |
| Recovery | `#D6E356` | `#5FC22E` | `#2A9440` |
| Sleep | `#A9B6F7` | `#6472DA` | `#3F45A8` |

Rings run light at the arc's start to deepest at its tip. The gradient compresses into
the drawn portion, so a 5% ring still reaches its deep colour.

### Meaning

| Token | Light | Dark | Use |
| --- | --- | --- | --- |
| `accent` | `#2FA84A` | `#54C96E` | Brand, primary actions, Jett |
| `onAccent` | `#FFFFFF` | `#0E0E10` | Labels on filled accent |
| `positive` | `#34A853` | `#5BD45B` | Favourable trend |
| `negative` | `#E9573F` | `#F07A64` | Unfavourable trend, errors |

A filled accent surface always uses `onAccent` for its label. White on the dark-mode
accent measures 2.23:1 and is a bug.

---

## 2. Type scale

SF Pro throughout. All numerals `.monospacedDigit()` so values do not jitter.

| Role | Size | Weight |
| --- | --- | --- |
| Hero figure (ring centre, detail) | 40 | semibold |
| Ring figure (Today) | 23 | semibold |
| Screen title | 22 | bold |
| Section heading | 18 | bold |
| Card title | 17 | semibold |
| Stat value | 26 | semibold |
| Body | 15–16 | regular |
| Secondary / caption | 13 | regular |
| Micro label | 12 | medium, uppercase, 0.6 tracking |

Micro labels (`COACHING`, `GOAL`) are the incumbent dashboard convention. Do not carry
that treatment into the conversation: message text uses `.body`, choices use
`.subheadline.weight(.medium)`, supporting choice text uses `.caption`, and metadata
uses `.caption2`. The contact name uses `.caption`, rising to `.body` at accessibility
sizes. These native text styles scale with Dynamic Type.

---

## 3. Shape and elevation

- **Card radius** 18, continuous
- **Inner element radius** 12–16, continuous
- **Pills and composers** capsule

Cards carry a **two-layer shadow** — one alone reads flat or muddy:

```
.shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
.shadow(color: .black.opacity(0.03), radius: 2,  x: 0, y: 1)
```

A card resting **on top of** another gets a heavier single shadow so its edge reads:

```
.shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 4)
```

This is how Today's rings sit on the coaching card — two surfaces, not one card with
a rule through it.

---

## 4. Spacing

- **Screen margin** 16
- **Between cards** 12
- **Between sections** 24
- **Card padding** 14–16
- **Row padding** 14 horizontal, 11–13 vertical

---

## 5. Components

| Component | What it is |
| --- | --- |
| `RingGauge` | Progress arc, gradient deepening to the tip, figure + `%` inside |
| `HeroRing` | `RingGauge` on a raised white disc, detail screens only |
| `StatCard` | Icon + label, value + unit, optional trend caret and range gauge |
| `RangeBar` | Where a reading sits in the user's own ±3 SD. Neutral track, a baseline tick at centre, a tinted dot. The track is never tinted — a glowing middle says the usual range is the alarming part |
| `ListCard` | Rows separated by hairlines inside one surface |
| `AccessoryRow` | Icon → label → chevron. The interactive idiom inside cards |
| `PrimaryButton` | Full-width filled action, takes the tint of its screen |
| `CoachCard` | `COACHING` label over a short paragraph |
| `TimelineRow` | Badged icon, title, subtitle, chevron |
| `PressableStyle` | 0.975 scale + 0.8 opacity on press |
| `FloatingTabBar` | Five slots on a floating white surface, inset 12 from the edges, radius 24 |
| `JettFace` | The coach. His portrait, circle-cropped, with a hairline edge |
| `CoachContactHeader` | Centered 42pt Jett portrait and name over a hairline; a real back action only in the live conversation |
| `CoachTurnView` | Shared incoming and outgoing Messages-style bubbles, including contextual reactions |
| `CoachComposer` | Multiline native message field and 44pt Send target, shared by onboarding and live coach |

**Buttons inside cards are accessory rows, not filled buttons.** Filled buttons are
reserved for the one primary action on a screen.

### The layered pair

When a conclusion and the thing it rests on belong together, they are **two surfaces,
not one card with a rule through it**. The top surface overlaps the lower one and
carries the heavier shadow, so its rounded bottom edge does the separating:

```
VStack(spacing: -18) {
    top.zIndex(1)          // heavier shadow, see §3
    bottom.padding(.top, 31)   // clears the 18pt overlap
}
```

Used for Today's rings over the coaching card, and Why's call over the plan. Reach for
it whenever the relationship is *rests on* — a verdict over its consequences, a figure
over its explanation. Not for two peers, which are two cards with a 12pt gap.

### Conversation and onboarding

**The Clear Next Step Rule.** Each onboarding question presents every supported answer
as a tappable choice. The opening names all four goals: get stronger, build muscle,
lose fat, and feel better. Frequency has four choices, followed by three experience levels. Obstacles expose all six options
with multi-select and Skip. Physical limitations offer three areas and None. Equipment follows
only for goals that imply lifting. Units offer pounds or kilos. Keep instructions short
and local to the action. Familiar users should be able to answer immediately.

The conversation uses one column with the contact header above it. Incoming messages
align left and outgoing messages align right. Bubbles hug their content, use the
frontmatter's message radius, and tighten the bottom corner on the speaker's side to
`rounded.message-tail`. Message padding is 15pt horizontal and 11pt vertical. Leave at
least 44pt on an outgoing message's opposite side and 36pt for an incoming one. There
is no shadow on either bubble.

The onboarding thread has 16pt side margins and 12pt gaps. Answer buttons form two
columns with 10pt gaps at ordinary sizes and one column at accessibility sizes. They
wrap naturally, have at least 52pt height, and use a 1pt blue border. A selected
obstacle has a checkmark, a full-strength border and a 10% blue fill. The latest answer
shows its Read time and an Edit action together until the Health read starts. Editing
removes that answer and its follow-up so the choice can be made again.

**The Contextual Reaction Rule.** Jett reacts after the user's answer is marked Read,
then sends his follow-up. The badge sits outside the upper-left edge of the outgoing
bubble, using `.topLeading` and an offset of -14pt horizontally and -16pt vertically;
reserve 12pt above the bubble.
Use `heart.fill` and `hand.thumbsup.fill` SF Symbols for heart and like. Muscle and
running reactions use their native emoji. Reaction descriptions belong in the
message's accessibility label. Add a reaction only when the answer calls for it.

Connect Health is the one filled action at that step. Explain its value in one short
message, with expandable category details and a Not now action. Only an explicit
Connect action requests Health permission; skipping persists across launches. After the sheet closes,
show the reading illustration with “Checking Health.” Both an empty read and an
available-data read lead to a useful conversation. Do not promise an immediate HRV
reading, a completed baseline, or a number of days that was not measured.

After Health, a single optional card shows only unknown height, birthday and biological
sex. Known values are never asked for. The attachment shows one focused selector at a time: a height ruler, inline birthday
wheel, or sex choices. Known fields are omitted. Unconfirmed previews stay unknown.
Each field can be skipped, and Skip rest continues with any already-confirmed values.
The birthday stays local; only age is included in the coach summary. No weight question.

Experience changes starter volume, effort and progression guidance. Equipment limits
starter exercises and substitutions, while physical limitations populate the profile
field the coach reads. Do not silently rewrite user-created plans or infer working weights.

The final step offers four starters covering training, recovery, sleep and nutrition.
Tapping one fills the composer so the user can edit it before sending. The first send
opens an explicit Anthropic consent sheet naming the shared data. Not now preserves
the draft; Explore the app first finishes without a provider request. Once permitted,
sending carries the exact question and existing transcript into the live coach once. The onboarding
thread itself is scripted and makes no coach-provider request.

The composer grows from one to four body-text lines. Its TextField keeps its intrinsic
vertical size so large text can wrap. The fixed 18pt Send symbol sits in a 36pt circle
inside a 44pt hit target. Disable sending whitespace or sending while a reply is in
progress. A concise disclosure accompanies the final composer: “Jett uses AI. You
choose what to share before your first reply.” The separate consent sheet identifies
Anthropic, messages/profile/check-ins/training, and derived Health summaries. Consent
can be revoked in Profile and is checked at the network boundary for every request.

### How an answer arrives

Jett's answer appears in a soft grey incoming bubble; the user's message appears in a
blue outgoing bubble. Onboarding and the live coach share `CoachTurnView`, the contact
header and the composer, so handing off the first question continues the same visual
conversation. Both speakers use regular body text. Charts requested by the live coach
remain inline within the incoming bubble and draw only from available device history.

While there is nothing to show, there is one quiet shimmering word and no container —
an empty bubble reads as a failure. A step the coach took is one line, past tense, with
a tick: what was done, never how the machinery works. Markdown is interpreted inline
only, because a block parser reflows the whole answer on every token and the paragraph
jumps around while you are reading it.

Haptics here are the faintest in the vocabulary: a half-intensity tap when the answer
*starts* — the moment the wait actually ended — and a selection tick when it finishes.
An answer arriving is not an achievement, and anything stronger would wear out fast and
drown the taps that mean something happened.

### Selling it

A list of features is a claim. The paywall runs Jett instead: the question appears, the
word shimmers, the answer lands, and the chart draws itself from **this user's own
history**. Nobody reads three bullet points about a coach, and everybody will watch one
work for eight seconds.

Only the demo changes size, so only the demo absorbs the slack: the prices and the
action are pinned, and the demo centres in what is left. Pinning them was not about
keeping them visible, though it does that — it is that a price which moves while you are
comparing two of them is worse than any amount of whitespace. Centring is the other half:
the same short scene pinned to the top of its space reads as a hole underneath it, and
centred reads as composed. Two charts at most here, because three made the tallest scene
six times the shortest and no layout absorbs that.

The script never states a measurement. The chart carries the specifics and it is real,
so the demo cannot promise something the data does not say. No countdown timers, no
invented discount: the saving badge is computed from the two real prices, because a
"save 40%" that does not match the receipt is a lie with a number on it.

### The goal-driven home

Today is not one screen. The rings, the coaching line and the health monitor are fixed;
everything between them is composed from the user's goal — see `HomeComposition`, which
is where the rule lives and where it is tested.

The rule: **the barbell angle is not the front page for everybody.** Someone who came
here to sleep better opens on their sleep and reaches their programme further down, if
they have one at all. A goal never promises a block the data cannot fill, and a block
with nothing behind it says what is missing rather than showing a confident zero.

Two consequences that are easy to miss: a lifting goal with no programme installed gets
*asked* rather than shown an empty screen, and copy that mentions "the session" has to
know whether there is one. Telling somebody with no programme to run the session as
planned names a thing that does not exist.

### The coach

The coach sits in the middle slot of the tab bar, not floating over the content. It is
the one control in the app with **no brand colour and no signal hue on it at all**: a
green logo in a circle reads as a widget somebody bolted on.

He is a **face**, and he is the only slot in the bar with no word under it. Everything
either side is an outline glyph with a label; this is a person, and the asymmetry is the
point — you do not need telling twice what it is, and the missing label is what makes
the slot read as somebody rather than as a destination.

**He is animated where he is present, and static where he is a button.** The coach
sheet and onboarding run the Rive file, switching to the static portrait with Reduce
Motion; the tab bar and the paywall use the PNG. A 38pt
face breathing permanently in the tab bar is noise, and the tab bar is somewhere you
tap rather than somewhere he is.

The `.riv` carries one artboard and one state machine, both named `Jett`, with three
inputs: `isThinking`, `isSpeaking`, `mood` (0 concerned, 1 neutral, 2 pleased). Blinking
and breathing run on their own timers **inside the file**, which is why there is no
trigger for either — the app must never have to remember to make him blink. Mood comes
from the day's call, so a bad morning shows on his face before he has said anything.

He was a ring for a while, and the ring was wrong. It was clean and it said nothing: the
app is already full of rings, so one more reads as a gauge rather than a person. A face
is the only element here somebody could feel they are talking to, which is the entire
job of a coach.

---

## 6. Rules

0. **The score is a weighted mean of z-scores against the user's own history**, and the
   weights are stated on the Profile screen. Sleep leads, then resting heart rate, then
   HRV. HRV is scored on its seven-day trend rather than one night, because it is the
   noisiest input here and a single night is mostly measurement rather than recovery.
   What is *displayed* is always today, so the words under a number describe that
   number; only the engine sees the smoothed figure.

1. **Never present missing measurements as a score.** Recovery and daily activity
   use personal percentiles. Sleep is a clearly explained deterministic estimate of
   duration, recorded continuity, and schedule consistency when available; duration
   alone never earns a sleep score. See `docs/briefs/signal-scores.md`. Food photos
   produce editable estimates, labelled as estimates and saved only after review.
2. **"No data" and "very low" must look different.** A ring with no history shows `—`;
   a terrible day shows its real figure with a visible arc floor.
3. **Colour never carries meaning that text does not also carry.**
   And where an indicator has both a direction and a verdict, they are separate facts:
   an arrow points the way the *measurement* moved, its colour says whether that is
   good news. A resting heart rate of 70 against a baseline of 53 points **up**, in
   red. Deriving the arrow from the verdict has now shipped this backwards twice.
4. **Arcs deepen toward their tip.** Every drawn arc runs light at its start to its
   deepest hue at the end of the line, and the gradient compresses into the drawn
   portion so a 5% ring still reaches full depth. A flat arc reads as a progress bar
   bent into a circle.
4. **Say it once.** If the rows below show it, the header does not repeat it.
   And never echo the user's own input back as a display — a meter showing the number
   they just entered tells them nothing. Their answers appear where they *explain*
   something, as evidence, not as decoration.
5. **Hug the content.** A container with empty space is a bug unless that space is
   reserved for something arriving.
6. **Stock components unless this document names an exception.** Reimplementing a
   native control is a defect. Sheets are `.sheet`/`.fullScreenCover` with the
   platform's own grabber and dismissal — never a bespoke panel with an X.
   *The one exception is the tab bar*, which floats and carries the coach in its
   middle slot. It is hand-built; everything else is not.
7. **Haptics only where something is committed or decided.** A set, a check-in, an
   applied change, an override, a timer expiring. Never on navigation or scrolling —
   except the coach portrait, which is the app's signature control and answers to the touch.

---

## 7. Motion

- Ring fill: `.easeOut(0.8)`, respects Reduce Motion
- Surface open/close: `.spring(response: 0.40, dampingFraction: 0.85)`
- Press: `.easeOut(0.12)`
- Coach button retract: `.easeOut(0.22)`

The scripted onboarding thread acknowledges the answer immediately with Sent, changes
to Delivered at 250ms, shows Read with the current time at 800ms, and adds the contextual
reaction at 980ms. Jett's follow-up arrives 1250–1630ms after the answer, with the final
pause varying by copy length. Intro and system turns use a 700ms beat. Only the latest
answer shows its receipt; once settled, its caption combines the Read time and Edit.
These receipts are part of the local scripted conversation, which makes no provider
request before the final question is sent.

The outgoing message uses a spring with response 0.3 and damping fraction 0.9. Replies
arrive with a 240ms ease-out and a small upward offset; reactions use a 200ms ease-out.
Onboarding scrolls to new content with `.easeOut(duration: 0.25)`.

Reduce Motion preserves the receipt and reply timing while removing message transforms
and springs. The contact portrait becomes static, reading arcs pause, the Thinking
shimmer stops and scrolling is immediate. The actual Health read keeps a minimum 1.3s
visible reading beat after the system sheet closes. It carries no fabricated percentage
or staged checklist.

Other animation entries above remain the incumbent vocabulary; each new animation
must honor Reduce Motion.

---

## 8. Accessibility

- Dynamic Type on every text element; hero numerals use `@ScaledMetric`
- Layout must survive AX XXXL — pinned elements unpin at accessibility sizes
- Minimum 44×44pt touch targets
- VoiceOver labels on every value and control; decorative charts are hidden
- Dark mode must not break

---

## 9. Voice

- Lead with the decision, not the data
- Short. If the screen shows it, do not write it
- Never grade a number — say where it sits ("Above usual"), not how good it is
- Keep the general medical/privacy explanation in Profile. The final onboarding
  composer adds the brief provider disclosure at the point of sending, followed by
  explicit permission before the first third-party AI request.
- **No em dashes.** They read as machine-written. A comma, a full stop, or a new
  sentence does the same job without the tell. The one exception is `—` standing alone
  as the "no value" glyph, which is a symbol rather than punctuation.
- **Any number that needs explaining carries an `InfoButton`.** Half of these are
  acronyms a watch started showing people without ever saying what they were. The
  explanation is plain language, says which direction means what, and never reads like
  a clinic.

### Jett

A coach who has been doing this long enough to be unimpressed by a bad night's sleep —
not an assistant. The difference is mostly what he leaves out.

**Shape.** The first line is the answer, under 15 words, and it stands alone: it is the
only line most people read. Then at most two short lines — the number that drove it, and
what to do. Under 60 words unless asked to go deeper. Message text uses regular body
style throughout; the writing carries the hierarchy. Scripted onboarding uses one
short question or instruction at a time, with choices available immediately below.

**Charts, not descriptions.** When the shape of a trend is the point, Jett writes
`[chart:hrv]` and the app draws that metric from history it already holds. The model
sends no data and makes no extra request: it names a metric in about six tokens, which
is cheaper than the sentence it replaces.

One chart per metric that genuinely drove the call, up to three. **Two things moving
together is the argument**, and stacking them is far more convincing than a sentence
listing them; a single metric on its own rarely makes the case. None when one number
already says it. Stacked charts use the compact card, because three full-height ones
push the point off the screen.

**An answer is one column: the call, the evidence, what to do.** The incoming bubble
contains that column. Inline charts have no additional card border; their labels stay
quieter than the body text. Scripted onboarding shows choices and an honest Health
result without inserting a metric chart.

**A chart replaces the sentence, it does not accompany it.** The chart already names the
metric and shows the number, so saying either again in prose is the single thing that
makes these answers feel bloated. With a chart, an answer is one line before it and one
line after it.

**Every chart says what it means.** A line on its own is a shape, and three stacked is
three shapes. Each carries one short line read off the data — "Lowest in 28 days",
"Sitting where it usually does" — derived rather than written by the model, so it can
never claim something the numbers do not show. Being at the edge of your own range beats
naming a direction, because it is the more useful fact and you can check it against the
picture.

Lines draw themselves and the figure counts along with the head, so the value shown is
always the value under the dot. The path is built point by point rather than trimmed,
since trimming walks arc length and the number drifts out of step on steep sections.

**Register.** Contractions, plain words, second person. "You're flat today", never "Your
readiness is reduced". Have an opinion and say it once rather than laying out both sides.

**What makes it read as a machine**, and is therefore banned: explaining the mechanism
when nobody asked, caveating out of politeness, recapping the question, summarising at
the end, and the openers — "Based on your data", "It looks like", "I'd recommend", "It's
important to", "Great question". Uncertainty appears only when it would change what
someone does today, and then in half a sentence.

He can be blunt. He is never chirpy.

## Asking about what already happened

**Ask after, not during.** A question about something the user is in the middle of is an
interruption; the same question an hour later costs nothing and the answer is worth the
same. The gym confirmation waits for the visit to end. The corollary is that the app has
to be willing to notice something and say nothing at the time.

**Never ask a question the phone could have answered.** "Do you lift here?" is a bad
question; "Do you lift at Club One?" is a good one, and the map knows the difference. One
named guess with a Yes, and the alternatives only for somebody who has already said no.

**A question is not the loudest thing on the screen.** It gets a small pill, not a
full-width button, however important the answer is to us. Colour still means what it
means everywhere else.

**Permission is asked for once, in front of the reason.** Never at launch, never before
the feature has been chosen. An explicit action such as Connect Health or a switch
change may raise a system dialog. A switch follows what the user asked for rather than
what iOS has granted so far, so it never flicks back while a dialog is still up.

**A switch row is tappable across its whole width.** A bare `Toggle` outside a `List`
only responds on the switch itself, which is a 50pt target hard against the right edge.
Wrap the row in a button and let the switch be the indicator.

## Motion that replaces words

Onboarding uses one native reading illustration during the Health read. `ReadingArt`
draws the existing strain, recovery and sleep colors as moving arcs around Jett at
150pt. Those arcs communicate activity, not a measured result or a percentage. The
contact portrait remains compact throughout the conversation.

Canvas and TimelineView use the app's existing tokens. Rive supplies Jett's character
motion. Reduce Motion pauses the arcs and substitutes `JettFace`. Keep motion attached
to a real state change or wait; the questions and choices need no decorative loops.

## The name

The product is **Coach Jett**. It was **Readiness**, and that word is still the name of
the thing the app computes: `ReadinessEngine` returns a `ReadinessResult`, the score on
the home screen is a readiness score, and none of that gets renamed. Product name and
domain vocabulary are separate, and collapsing them would cost us the only word that
accurately describes what the number is.

The bundle id moved with the name, to `com.coachjett.ios`, and that was only cheap
because nothing had shipped. A bundle id is the identity every stored thing hangs off:
HealthKit authorisation, UserDefaults, the local store, the keychain, the StoreKit
product ids. Changing it after a release orphans all of them on every existing install.
Before the first release it costs one rebuild. There is no third option, so it happens
now or never.

What stayed behind, on purpose: the Xcode project, target and scheme, the
`ReadinessCore` package, and the file names. All invisible to users, all pure churn.

**The icon is Jett's face on his own purple**, not on the brand green. Green means "an
action you take" everywhere else in the app, and an icon is not an action. It is the same
artwork as the face in the tab bar, so the thing you tap on the home screen and the thing
that talks to you inside are recognisably one character.


### Multiple goals
The opening goal chips support multiple selections. Ask "What would you like to work on? Pick any that apply." A tap toggles a visible checkmark and selected fill; Continue stays disabled until at least one goal is selected. Only Continue sends the combined answer, in stable chip order. Editing that reply restores every selected chip. Keep the opening message animations and reply receipts.

Store the full goal set in the existing onboarding JSON, read legacy single-goal answers, and expose the same multi-selection in Profile. Keep at least one Profile goal. The complete set determines home cards without duplicates and the context sent to Jett. Ask equipment if any selected goal implies lifting; a Feel better/Lose fat combination skips it. The old profile goal column is a compatibility marker, not a user-ranked primary goal.


## September 19 hands-on critique pass

Keep Home actions direct: one Nutrition card for calories and all macros, camera-first
Log meal, current weight with Log weight, one-line check-in, editable today's workout,
and plain-English Health Monitor rows. No calorie deficit claim from partial meal logs.
Use the Messages onboarding voice: acknowledge the actual answers, modest humor for
positive goals, empathetic words rather than celebration badges for obstacles/injuries.
Weight logs are new measurements, with local persistence and explicit Health save status.
Meal exports carry individual IDs so Health imports and local entries count exactly once.
