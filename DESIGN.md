# Design system

The spec for how this app looks and behaves. Edit this file; `App/Design/Tokens.swift`
and `App/Design/Components.swift` implement it.

Every value here is what is actually in the build today, not an aspiration.

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

Micro labels (`COACHING`, `GOAL`) are the only place small caps and tracking are used.

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

### How an answer arrives

The coach's text is **not a bubble**. A bubble is for something somebody said to you; an
answer is the content of the screen, so it runs full width in plain prose and only the
user's own message gets a container. That one choice is most of what separates a chat
toy from a tool.

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

1. **Never show a number the app did not measure.** No invented scores. Ring figures
   are percentiles against the user's own history, share of a target, or share of a
   typical week — all real quantities.
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
   except the coach orb, which is the app's signature control and answers to the touch.

---

## 7. Motion

- Ring fill: `.easeOut(0.8)`, respects Reduce Motion
- Surface open/close: `.spring(response: 0.40, dampingFraction: 0.85)`
- Press: `.easeOut(0.12)`
- Coach button retract: `.easeOut(0.22)`

Every animation checks `accessibilityReduceMotion`.

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
- One medical/privacy disclaimer, in Profile, nowhere else
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
what to do. Under 60 words unless asked to go deeper. The view sets that first line as a
headline, so a rambling opener has nowhere to hide.

**Charts, not descriptions.** When the shape of a trend is the point, Jett writes
`[chart:hrv]` and the app draws that metric from history it already holds. The model
sends no data and makes no extra request: it names a metric in about six tokens, which
is cheaper than the sentence it replaces.

One chart per metric that genuinely drove the call, up to three. **Two things moving
together is the argument**, and stacking them is far more convincing than a sentence
listing them; a single metric on its own rarely makes the case. None when one number
already says it. Stacked charts use the compact card, because three full-height ones
push the point off the screen.

**An answer is one column: the call, the evidence, what to do.** Nothing else. The
charts sit in that column without a card around them, because a bordered box in the
middle of a thought reads as an interruption rather than as the evidence for the
sentence above it. Three weights carry the structure: the call in bold primary, the
action in secondary, the chart's own read a step quieter than both.

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
