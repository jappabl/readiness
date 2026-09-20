# Telling "missing today" apart from "your phone cannot measure this"

**Status:** proposed, for review
**Scope:** what the app says about data it does not have

## The problem

A phone-only sleeper — no watch, and the commonest first-run profile there is — gets a
sleep score built from duration, continuity and bedtimes. They cannot have sleep stages or
an overnight heart-rate dip, ever, because nothing on their person measures those.

Every morning the app lists what it could not count:

> **Not counted today**
> Seven nights of stage data for deep sleep
> Seven nights of stage data for REM
> Seven nights of stage data for awakenings
> Overnight and daytime heart rate

Four reasons, none of which will ever be satisfied, repeated daily forever. Until this
week it was worse — the heading read *"Still learning your normal"*, which promises that
waiting fixes it. That heading is fixed. The list underneath is not.

The same shape applies elsewhere: recovery names four missing streams for this user, and
onboarding's reveal has nothing to draw.

## The distinction the app does not currently make

Two different facts are rendered identically:

| | meaning | what the user can do |
|---|---|---|
| **Absent today** | usually recorded, not last night | wear the watch, charge it |
| **Absent structurally** | never recorded, no sensor for it | nothing |

Only the first is worth a line on a daily screen. The second is worth saying **once**, and
never again.

## Proposal

### 1. Detect structural absence from the record, not from a device list

A stream is *structurally absent* when the record is long enough to have shown it and
never has:

```
structurallyAbsent(stream) =
    daysOfHistory >= BaselineSummary.minimumReadings   // 7
    && days carrying that stream == 0
```

No device inventory, no HealthKit capability query, no user question. It is self-correcting
in both directions: buy a watch and stage rows appear within a week; stop wearing it and
they go back to being "absent today" first, then structural after seven empty days.

**Open question for review:** seven days may be too eager. A week's holiday without the
watch would reclassify a watch user as structural, and they would lose the daily nudge that
their watch is off. Alternatives: require the stream to have *never* appeared in the whole
record, or use a longer threshold (28 days) for the transition into structural and a short
one out of it.

### 2. Three states, not two

| coverage | when | heading |
|---|---|---|
| `.full` | everything this person can record, recorded | — |
| `.partial` | something usually present is absent today | "Not counted today" |
| `.buildingBaseline` | the record is too short to judge against | "Still learning your normal" |

Structurally absent streams are **excluded from the missing list entirely** and do not
push coverage below `.full`. A phone-only sleeper who slept and whose sleep was recorded
has a complete record *for their device*, and the score should say so.

This is the substantive behaviour change: today that user can never see `.full`.

### 3. Say it once, where it belongs

Onboarding's last screen already tells people what the app read. It gains one line naming
what it will never read, in terms of what it costs them:

> Sleep stages and overnight heart rate need a watch. Without one I score your nights on
> how long and how unbroken they were, which is most of it.

Not a nag, not a purchase prompt, and not repeated. If they later connect a watch, the
rows appear on their own and need no announcement.

### 4. The score itself does not change

Structural absence already behaves correctly in the maths: a missing component is charged
`typicalComponentLevel`, which stops a phone scoring 100 on a night a watch could only
score 96. That stays exactly as it is. This proposal changes **what is said**, not what is
computed.

## What this does not fix

- A phone-only user's *recovery* ring is still built from sleep debt alone, with the night
  standing in. That is a separate piece, already done and tested.
- The stand-in still flatters a genuinely rough night nobody measured. Unfixable; recorded
  in `PartialStagingTests`.

## Cost

Four files: `ScoreCoverage` gains no cases, `SleepScore.of` and `RecoveryScore.of` filter
their missing lists, `DailyPhysiology` gains a per-stream presence count, onboarding gains
one sentence. No change to any scoring path, so the existing suite should stay green
without edits — which is also the check that this is presentation-only.

## Decision needed

1. The seven-day threshold, or one of the alternatives in §1.
2. Whether a structurally-absent stream should really allow `.full`, or whether coverage
   should stay `.partial` with an empty list. `.full` is the honest answer for that device;
   `.partial` is more conservative and keeps the ring's track visibly incomplete.
