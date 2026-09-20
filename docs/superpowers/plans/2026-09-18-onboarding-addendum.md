# Conversation personalization implementation plan

Goal: add experience, physical limitations and lifting-only equipment turns, plus read-first Health details with an optional missing-fields fallback.
Spec: docs/briefs/conversational-onboarding.md and the user's addendum, including the subsequent missing-details correction.
Architecture: Core owns sequence, completeness, backwards-compatible answers, profile validation/merging and training defaults. SwiftUI renders choices. The existing single Health request gains three read types. Manual missing details stay in the existing answers JSON; the coach receives age rather than birthday.

## Constraints
- Preserve existing Messages styling, pacing, consent and one-shot handoff. No new provider calls during onboarding.
- Order: goal, frequency, experience, obstacles, limitations, equipment only for impliesLifting, units, Health, missing details if needed, final question.
- No weight, referral, goal weight or rate-of-change questions. Health details are never asked before Health; fallback is optional and only for missing fields.
- Declined/empty/invalid Health values remain unknown. Every fallback field may be skipped. Birthday has no default answer and never enters the coach payload.
- Decode existing answer JSON safely. Persist limitations to the profile field already consumed by the coach.
- Equipment limits the starter catalog and coach substitutions. Experience changes starter volume/effort and progression guidance; physical load increments remain equipment constraints.
- No modifications to unrelated concurrent work and no commit.

## Work
- [x] Write failing Core tests for frequency -> experience, lifting/nonlifting branches, recent-answer edits, limitations-none, legacy JSON, completion, partial Health fallback, skip, birthday validation, age calculation and no DOB in coach JSON.
- [x] Add OnboardingAnswers fields/types and conversation actions; ensure a nonlifting route requires no equipment and edits cannot leave stale branch data.
- [x] Add HealthProfile validation/merge and CoachProfileSummary. Add height to readTypes and fetch latest height outside the 180-day history window; characteristics use existing Health store APIs after the single authorization.
- [x] Persist manual fallback in answers JSON and limitations in profile.limitations. Include experience, equipment, limitations and derived demographics in both populated and missing-readiness coach contexts.
- [x] Write failing starter-plan tests for equipment legality, novice/experienced targets, limitations and substitution allowlists. Implement Core starter catalog and wire ProgramSetupView to it, keeping user-authored templates intact.
- [x] Render the three new chip turns and one compact optional missing-details card. Use a height ruler, inline native birthday wheel, explicit sex choices, per-field Skip and accessible layouts. Only confirmed selector values are saved.
- [x] Update consent disclosure/version for age/height/sex summaries; update the brief and DESIGN.
- [x] Run full Core tests, app integration checks, native build and diff checks. Review the implementation and refresh graphify.
- [x] Visually verify lifting and Feel better paths, None and multiple limitations, missing details, Skip, known-field omission, normal/large type and dark appearance; save evidence and refresh the demo.

## Verification evidence
- 288 Swift Testing tests in 43 suites passed on the final Core sources; tested/staged sources match the actual project.
- Final iOS Simulator build succeeded. `git diff --check` passed.
- Native Health read-set integration check found height, DOB and biological sex in the existing request (34 read types total). No extra authorization site.
- Native lifting route: novice, knee limitation, dumbbells; Profile displays Knees.
- Native nonlifting route: Feel better skips equipment; None clears limitations.
- Optional details: skipping height and birthday saves neither preview. Confirming height on the next run preserves previously known sex. Known fields are omitted; birthday-only fallback verified.
- Initial ruler misalignment reproduced visually and fixed with explicit initial centering. Initial and Back positions verified at 170 cm.
- Normal and largest Dynamic Type layouts inspected; dark appearance inspected. Native gestures remain a hands-on QA item: the UI automation service returns `noWindowsAvailable` for coordinate/scroll gestures, though accessibility-button actions work. Unit conversion and bounds were source-reviewed, not gesture-tested.
- Read-only reviewer found no remaining important issues. No live coaching/provider request was sent.
- User-facing demo and screenshots: outputs/conversational-onboarding/addendum in the Codex task workspace. Demo removes only long static QA pauses, preserving animation speed.
