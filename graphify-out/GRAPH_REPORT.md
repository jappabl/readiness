# Graph Report - readiness  (2026-09-19)

## Corpus Check
- 189 files · ~510,510 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1308 nodes · 2017 edges · 83 communities detected
- Extraction: 89% EXTRACTED · 11% INFERRED · 0% AMBIGUOUS · INFERRED: 228 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `1344e1b4`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]
- [[_COMMUNITY_Community 69|Community 69]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 71|Community 71]]
- [[_COMMUNITY_Community 72|Community 72]]
- [[_COMMUNITY_Community 73|Community 73]]
- [[_COMMUNITY_Community 74|Community 74]]
- [[_COMMUNITY_Community 75|Community 75]]
- [[_COMMUNITY_Community 76|Community 76]]
- [[_COMMUNITY_Community 77|Community 77]]
- [[_COMMUNITY_Community 78|Community 78]]
- [[_COMMUNITY_Community 79|Community 79]]
- [[_COMMUNITY_Community 80|Community 80]]
- [[_COMMUNITY_Community 81|Community 81]]
- [[_COMMUNITY_Community 82|Community 82]]

## God Nodes (most connected - your core abstractions)
1. `Sendable` - 76 edges
2. `View` - 60 edges
3. `Equatable` - 50 edges
4. `Codable` - 41 edges
5. `OnboardingConversation` - 41 edges
6. `AppModel` - 36 edges
7. `ReadinessInput` - 31 edges
8. `RecommendationInput` - 29 edges
9. `String` - 28 edges
10. `readiness()` - 23 edges

## Surprising Connections (you probably didn't know these)
- `Exercise` --inherits--> `Sendable`  [EXTRACTED]
  Core/Sources/ReadinessCore/StarterPrograms.swift → App/Coach/CoachProvider.swift
- `Lift` --inherits--> `Sendable`  [EXTRACTED]
  Core/Sources/ReadinessCore/PrescriptionEngine.swift → App/Coach/CoachProvider.swift
- `Lift` --inherits--> `Equatable`  [EXTRACTED]
  Core/Sources/ReadinessCore/PrescriptionEngine.swift → App/Coach/CoachProvider.swift
- `Lift` --inherits--> `Codable`  [EXTRACTED]
  Core/Sources/ReadinessCore/PrescriptionEngine.swift → App/Data/Models.swift
- `Prescription` --inherits--> `Sendable`  [EXTRACTED]
  Core/Sources/ReadinessCore/PrescriptionEngine.swift → App/Coach/CoachProvider.swift

## Communities (125 total, 41 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.05
Nodes (16): AppIntent, AppShortcutsProvider, CheckInRow, DailyMetricRow, LoggedSet, MealLog, RecommendationRow, Store (+8 more)

### Community 1 - "Community 1"
Cohesion: 0.05
Nodes (17): AssembledDay, DayAssembler, BaselineEngine, BaselineResult, MetricReading, ReadinessInput, CoachBriefTests, DirectionTests (+9 more)

### Community 2 - "Community 2"
Cohesion: 0.05
Nodes (13): HealthKitSeeder, HealthKitSource, HKUnit, Stream, DailyPhysiology, HealthSource, Generator, SyntheticHealthSource (+5 more)

### Community 3 - "Community 3"
Cohesion: 0.07
Nodes (5): CoachContextBuilder, OnboardingConversation, Turn, MultipleGoalsTests, OnboardingConversationTests

### Community 4 - "Community 4"
Cohesion: 0.11
Nodes (8): RecommendationEngine, RecommendationInput, CheckIn, AdjustmentTests, CheckInTests, EvidenceTests, readiness(), TrainingStateTests

### Community 5 - "Community 5"
Cohesion: 0.06
Nodes (6): daily, HomeCompositionTests, ACWRTests, NoveltyTests, set(), StrainEngineTests

### Community 6 - "Community 6"
Cohesion: 0.07
Nodes (12): CoachMessage, TemplateExercise, WorkoutTemplate, Identifiable, CoachTurnView, OnboardingView, View, ExerciseEditorRow (+4 more)

### Community 7 - "Community 7"
Cohesion: 0.07
Nodes (32): CaseIterable, RecommendationResponse, accepted, modified, rejected, Signal, recovery, sleep (+24 more)

### Community 8 - "Community 8"
Cohesion: 0.09
Nodes (8): DailyActivity, DailyStrain, DailyStrainCoverage, buildingBaseline, recordedZero, relativeToHistory, DailyStrainTests, SleepScoreTests

### Community 9 - "Community 9"
Cohesion: 0.09
Nodes (4): CLLocationManagerDelegate, GymPresence, GymVisit, GymDetectorTests

### Community 10 - "Community 10"
Cohesion: 0.08
Nodes (5): PlannedExercise, ProposedExercise, SessionPlanner, CoachToolsTests, SessionPlannerTests

### Community 11 - "Community 11"
Cohesion: 0.07
Nodes (25): CoachError, declined, notConfigured, sharingNotAllowed, transport, CoachEvent, text, toolCall (+17 more)

### Community 12 - "Community 12"
Cohesion: 0.13
Nodes (23): AccessoryRow, CoachCard, FieldRow, FloatingTabBar, HeroRing, JettFace, ListCard, PrimaryButton (+15 more)

### Community 13 - "Community 13"
Cohesion: 0.14
Nodes (16): CoachToolCall, Equatable, CoachContext, CoachContextBuilder, DaySummary, ExerciseSummary, MetricSummary, DailyStrainResult (+8 more)

### Community 14 - "Community 14"
Cohesion: 0.1
Nodes (11): experienced, Equipment, barbell, bodyweight, dumbbells, machine, Exercise, Plan (+3 more)

### Community 15 - "Community 15"
Cohesion: 0.09
Nodes (8): ButtonStyle, CoachSheet, PressableStyle, View, BirthdayPicker, HeightRuler, OnboardingHealthDetailsView, PaywallView

### Community 16 - "Community 16"
Cohesion: 0.11
Nodes (20): Codable, KnownGym, InputContribution, ReadinessConfidence, low, normal, ReadinessEngine, ReadinessGate (+12 more)

### Community 17 - "Community 17"
Cohesion: 0.09
Nodes (8): NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIViewControllerRepresentable, Coordinator, MealCamera, MealLogView, WeightLogView

### Community 18 - "Community 18"
Cohesion: 0.1
Nodes (3): PlateMathTests, PrescriptionBoundsTests, PrescriptionMappingTests

### Community 19 - "Community 19"
Cohesion: 0.14
Nodes (7): EmptyBlock, EnergyBalanceCard, MovementCard, NutritionCard, ProteinCard, SleepQualityCard, WeightTrendCard

### Community 20 - "Community 20"
Cohesion: 0.12
Nodes (8): ClaudeCoachProvider, Keychain, Turn, CoachUsage, RehearsalCoachProvider, CoachProvider, Error, InvalidEstimate

### Community 24 - "Community 24"
Cohesion: 0.12
Nodes (15): MuscleGroup, arms, back, chest, core, glutes, hamstrings, quads (+7 more)

### Community 25 - "Community 25"
Cohesion: 0.16
Nodes (6): HealthContext, Metric, Observation, Stream, InsightEngine, TrainingDay

### Community 26 - "Community 26"
Cohesion: 0.16
Nodes (4): DrawingLine, Arc, ReadingArt, ReadingRive

### Community 28 - "Community 28"
Cohesion: 0.17
Nodes (10): CoachSegment, chart, text, CoachSegments, MetricKind, bloodOxygen, hrv, respiratoryRate (+2 more)

### Community 29 - "Community 29"
Cohesion: 0.15
Nodes (11): HomeBlock, energyBalance, healthMonitor, movement, nutrition, programPrompt, protein, session (+3 more)

### Community 30 - "Community 30"
Cohesion: 0.17
Nodes (12): Step, equipment, experience, frequency, goal, health, healthDetails, limitations (+4 more)

### Community 35 - "Community 35"
Cohesion: 0.22
Nodes (7): Failure, invalidPhoto, invalidResponse, missingKey, service, MealPhotoEstimator, MealPhotoKey

### Community 40 - "Community 40"
Cohesion: 0.2
Nodes (9): BiologicalSex, female, male, other, CoachProfileSummary, Field, biologicalSex, dateOfBirth (+1 more)

### Community 41 - "Community 41"
Cohesion: 0.24
Nodes (6): SleepScore, SleepScoreCoverage, durationAndContinuity, durationContinuityAndSchedule, durationOnly, missing

### Community 50 - "Community 50"
Cohesion: 0.25
Nodes (3): BodyMass, FoodNumber, MealEstimate

### Community 51 - "Community 51"
Cohesion: 0.25
Nodes (8): Hashable, SessionAdjustment, capEffort, deferLowerBody, proceedAsPlanned, reduceLoad, reduceWorkingSets, swapConditioningToZone2

### Community 55 - "Community 55"
Cohesion: 0.38
Nodes (3): Lift, Prescription, PrescriptionEngine

### Community 56 - "Community 56"
Cohesion: 0.29
Nodes (7): SleepStage, awake, core, deep, inBed, rem, unspecified

### Community 57 - "Community 57"
Cohesion: 0.29
Nodes (3): AdjustSessionView, PlannedSessionCard, ProposedExerciseRow

### Community 61 - "Community 61"
Cohesion: 0.47
Nodes (3): BurstLimiter, Decision, State

### Community 62 - "Community 62"
Cohesion: 0.33
Nodes (6): DailyStrainMetric, activeEnergy, exerciseMinutes, steps, workoutEnergy, workoutMinutes

### Community 63 - "Community 63"
Cohesion: 0.33
Nodes (6): SetFeel, easy, grindy, heavy, painful, smooth

### Community 65 - "Community 65"
Cohesion: 0.33
Nodes (4): App, ReadinessApp, RootView, View

### Community 67 - "Community 67"
Cohesion: 0.4
Nodes (5): TrainingGoal, buildMuscle, feelBetter, getStronger, loseFat

### Community 68 - "Community 68"
Cohesion: 0.4
Nodes (5): CoachReaction, heart, like, muscle, running

### Community 81 - "Community 81"
Cohesion: 0.67
Nodes (3): Trend, down, up

## Knowledge Gaps
- **157 isolated node(s):** `chart`, `heart`, `like`, `muscle`, `running` (+152 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **41 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Sendable` connect `Community 13` to `Community 0`, `Community 1`, `Community 2`, `Community 3`, `Community 4`, `Community 7`, `Community 8`, `Community 9`, `Community 10`, `Community 11`, `Community 14`, `Community 16`, `Community 24`, `Community 25`, `Community 28`, `Community 29`, `Community 30`, `Community 34`, `Community 40`, `Community 41`, `Community 47`, `Community 50`, `Community 51`, `Community 55`, `Community 56`, `Community 61`, `Community 62`, `Community 63`, `Community 67`, `Community 68`?**
  _High betweenness centrality (0.312) - this node is a cross-community bridge._
- **Why does `View` connect `Community 12` to `Community 65`, `Community 58`, `Community 6`, `Community 70`, `Community 73`, `Community 74`, `Community 75`, `Community 42`, `Community 43`, `Community 76`, `Community 15`, `Community 80`, `Community 17`, `Community 19`, `Community 53`, `Community 57`, `Community 26`?**
  _High betweenness centrality (0.138) - this node is a cross-community bridge._
- **Why does `Equatable` connect `Community 13` to `Community 0`, `Community 1`, `Community 2`, `Community 3`, `Community 4`, `Community 6`, `Community 7`, `Community 8`, `Community 9`, `Community 10`, `Community 16`, `Community 24`, `Community 25`, `Community 28`, `Community 29`, `Community 34`, `Community 40`, `Community 41`, `Community 47`, `Community 51`, `Community 55`, `Community 56`, `Community 61`, `Community 62`, `Community 67`?**
  _High betweenness centrality (0.121) - this node is a cross-community bridge._
- **Are the 16 inferred relationships involving `OnboardingConversation` (e.g. with `.skipHealth()` and `.selectingSeveralGoalsWaitsForConfirmation()`) actually correct?**
  _`OnboardingConversation` has 16 INFERRED edges - model-reasoned connections that need verification._
- **What connects `chart`, `heart`, `like` to the rest of the system?**
  _157 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.05 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.05 - nodes in this community are weakly interconnected._