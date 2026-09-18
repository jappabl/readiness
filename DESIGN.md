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
| `RangeBar` | Where a reading sits in the user's own ±3 SD, polarity-adjusted |
| `SegmentedMeter` | Discrete ticks filled to a share |
| `ListCard` | Rows separated by hairlines inside one surface |
| `AccessoryRow` | Icon → label → chevron. The interactive idiom inside cards |
| `PrimaryButton` | Full-width filled action, takes the tint of its screen |
| `CoachCard` | `COACHING` label over a short paragraph |
| `TimelineRow` | Badged icon, title, subtitle, chevron |
| `PressableStyle` | 0.975 scale + 0.8 opacity on press |

**Buttons inside cards are accessory rows, not filled buttons.** Filled buttons are
reserved for the one primary action on a screen.

---

## 6. Rules

1. **Never show a number the app did not measure.** No invented scores. Ring figures
   are percentiles against the user's own history, share of a target, or share of a
   typical week — all real quantities.
2. **"No data" and "very low" must look different.** A ring with no history shows `—`;
   a terrible day shows its real figure with a visible arc floor.
3. **Colour never carries meaning that text does not also carry.**
4. **Say it once.** If the rows below show it, the header does not repeat it.
5. **Hug the content.** A container with empty space is a bug unless that space is
   reserved for something arriving.
6. **Stock components unless this document names an exception.** Reimplementing a
   native control is a defect. Sheets are `.sheet`/`.fullScreenCover` with the
   platform's own grabber and dismissal — never a bespoke panel with an X.
7. **Haptics only where something is committed or decided.** A set, a check-in, an
   applied change, an override, a timer expiring. Never on navigation or scrolling.

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
