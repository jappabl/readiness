# Telling "missing today" apart from "your phone cannot measure this"

**Status:** approved, not yet built
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

### 1. Ask, then watch the data

Onboarding asks once: **do you wear a watch to bed?** That answer is the starting state,
and the record corrects it from there. Four states, and the transitions are the whole
feature:

| they said | data says | what happens |
|---|---|---|
| yes | stages arriving | nothing — normal operation |
| **yes** | **nothing, 7 days** | **nudge: the watch is not being worn to bed** |
| no | nothing | stage rows never mentioned again |
| **no** | **stages start arriving** | **"you got a watch" — congratulate, then confirm** |

Only the two bold rows say anything. The answer is a starting point, never a lock: somebody
who buys a watch six months in is recognised by their data, not asked again.

Asymmetric thresholds, because the two errors are not equal:

- **Into "no watch": 28 days.** A fortnight's holiday must not reclassify a watch owner
  and silence the nudge that their watch is off.
- **Out of "no watch": 7 days** — one week of stage data is enough to say a watch has
  appeared, and the congratulation should not lag a month behind the purchase.

### 2. Three states, not two

| coverage | when | heading |
|---|---|---|
| `.full` | everything this person can record, recorded | — |
| `.partial` | something usually present is absent today | "Not counted today" |
| `.buildingBaseline` | the record is too short to judge against | "Still learning your normal" |

Streams the person has no sensor for are **excluded from the missing list entirely** and do
not push coverage below `.full`. **Decided: a phone-only sleeper can see a complete score.**
Their record is complete for the device they own, and never being able to see a full ring
is the actual complaint.

### 3. The nudges

Two, both rare, neither repeating:

- *Watch not worn:* once, after seven empty nights against a "yes" answer. Not daily.
- *Watch detected:* once, when stages appear against a "no" answer. Confirm rather than
  assume — a single night of stage data could be a borrowed device or a one-off.

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

## Decided

1. Ask in onboarding; correct from the data. 28 days into "no watch", 7 days out.
2. A phone-only sleeper can reach `.full`.

## Still open

Where the two nudges appear. The coach stream is the obvious home for both, but "you got a
watch" is a moment and might be worth more than a chat line.
