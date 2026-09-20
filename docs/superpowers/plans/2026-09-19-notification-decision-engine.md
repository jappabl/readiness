# Notification Decision Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Swift decision layer in `ReadinessCore` that answers "should Coach Jett speak right now, about which moment, and in what words" — with no iOS API surface, so every product decision in the spec is provable by `swift test`.

**Architecture:** Five small `public enum` namespaces of static functions, following the existing `ReadinessCore` idiom (`BurstLimiter`, `InsightEngine`, `RecommendationEngine`). Each moment gets its own type that answers one question and returns `String?` — nil meaning "nothing worth saying". A top-level `NotificationDecision.next(_:)` runs them in priority order and applies the speaking budget. Nothing here imports `UserNotifications`, `HealthKit`, `SwiftUI` or `CoreLocation`.

**Tech Stack:** Swift 6.2, Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`), swift-tools-version 6.0, iOS 17 / macOS 14 platform floor.

**Spec:** `docs/superpowers/specs/2026-09-19-notifications-design.md`

## Global Constraints

- **Pure functions only.** No `Foundation` beyond `Date`, `Calendar`, `TimeInterval`. No I/O, no singletons, no `UserDefaults`. Every function takes `now: Date` rather than calling `Date()`.
- **Swift Testing, not XCTest.** `import Testing`, `@Suite("...")`, `@Test("...")`, `#expect(...)`. Match `Core/Tests/ReadinessCoreTests/BurstLimiterTests.swift` for style.
- **Every new Core file needs four `project.pbxproj` edits**, because that file is hand-written and Core sources are compiled into the app target as well as the SPM package. Pattern them on `BurstLimiter.swift` at lines 74, 167, 372, 535. After every edit: `plutil -lint Readiness.xcodeproj/project.pbxproj`.
- **Run `swift test` from the repo root** — the `Package.swift` at root points at `Core/Sources/ReadinessCore` and `Core/Tests/ReadinessCoreTests`.
- **`BurstLimiter.swift` must not be modified.** The coach depends on it with its own constants.
- **Notification strings live in Core, beside the engine.** This refines the spec, which said `Copy.swift`: that file is in `App/Domain/` and unreachable from a `swift test` run, which would make the copy unprovable. Core already owns user-facing prose (`SignalScore.summary`, `ReadinessGate.explanation`), so the spec's actual intent — one voice, kept together, never model-generated — is preserved. `App/Domain/Copy.swift` remains for view copy.
- **Budget status per moment, copied verbatim from the spec:** morning verdict — not budgeted; illness gate — not budgeted; gym arrival — not budgeted and never reaches this engine (it is location-driven, App-side); new insight — budgeted; bedtime target — budgeted.
- **Never call `Date()` inside a decision function.** Tests pin `Date(timeIntervalSince1970: 1_800_000_000)` as a start instant, as `BurstLimiterTests` does.

---

### Task 1: The vocabulary — `NotificationMoment`

**Files:**
- Create: `Core/Sources/ReadinessCore/NotificationMoment.swift`
- Modify: `Readiness.xcodeproj/project.pbxproj`
- Test: `Core/Tests/ReadinessCoreTests/NotificationMomentTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public enum NotificationMoment: String, Sendable, Codable, Equatable, CaseIterable` with cases `morningVerdict`, `illnessGate`, `newInsight`, `bedtimeTarget`, and `public var spendsBudget: Bool`.

- [ ] **Step 1: Write the failing test**

Create `Core/Tests/ReadinessCoreTests/NotificationMomentTests.swift`:

```swift
import Testing
@testable import ReadinessCore

/// Which moments compete for an allowance and which are exempt. The morning verdict is
/// the app's core output, not one nice-to-have among several, so it never queues behind
/// an insight.
@Suite("What a notification moment costs")
struct NotificationMomentTests {

    @Test("the core output and the illness gate are free")
    func exemptMoments() {
        #expect(!NotificationMoment.morningVerdict.spendsBudget)
        #expect(!NotificationMoment.illnessGate.spendsBudget)
    }

    @Test("the extras are budgeted")
    func budgetedMoments() {
        #expect(NotificationMoment.newInsight.spendsBudget)
        #expect(NotificationMoment.bedtimeTarget.spendsBudget)
    }

    @Test("every moment has an answer, so a new case cannot be forgotten")
    func everyCaseIsClassified() {
        #expect(NotificationMoment.allCases.count == 4)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NotificationMomentTests`
Expected: FAIL — `cannot find 'NotificationMoment' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Core/Sources/ReadinessCore/NotificationMoment.swift`:

```swift
import Foundation

/// The occasions on which Coach Jett initiates a message.
///
/// Gym arrival is deliberately absent. It is transactional rather than editorial — it
/// responds to something the user just did, the way a delivery notification does — and
/// it is decided by CoreLocation in the app layer, so it never reaches this engine and
/// never competes for the allowance the initiated messages share.
///
/// See docs/superpowers/specs/2026-09-19-notifications-design.md.
public enum NotificationMoment: String, Sendable, Codable, Equatable, CaseIterable {
    case morningVerdict
    case illnessGate
    case newInsight
    case bedtimeTarget

    /// Whether this moment draws from the speaking budget.
    ///
    /// The morning verdict does not. Budgeting it would treat "how did I sleep" as one
    /// nice-to-have among several, when it is the thing the user opened an account for —
    /// and it would silence the fifth consecutive rough night, which is a fifth day they
    /// should train differently.
    public var spendsBudget: Bool {
        switch self {
        case .morningVerdict, .illnessGate: return false
        case .newInsight, .bedtimeTarget: return true
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NotificationMomentTests`
Expected: PASS, 3 tests.

- [ ] **Step 5: Register the file in the app target**

`Readiness.xcodeproj/project.pbxproj` needs four edits. Generate two fresh 24-character uppercase-hex IDs that do not already appear in the file. Grep the file **as it stands right now**, not as the plan shows it — earlier tasks have already added IDs of their own: `grep -c '<candidate>' Readiness.xcodeproj/project.pbxproj` must print `0` for both before you use them. Call them `BUILDID` and `FILEID`.

1. In the `PBXBuildFile` section (near line 74, beside the `BurstLimiter.swift` entry):
   `		BUILDID /* NotificationMoment.swift in Sources */ = {isa = PBXBuildFile; fileRef = FILEID /* NotificationMoment.swift */; };`
2. In the `PBXFileReference` section (near line 167):
   `		FILEID /* NotificationMoment.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "NotificationMoment.swift"; sourceTree = "<group>"; };`
3. In the ReadinessCore group's `children` array (near line 372):
   `				FILEID /* NotificationMoment.swift */,`
4. In the Sources build phase `files` array (near line 535):
   `				BUILDID /* NotificationMoment.swift in Sources */,`

- [ ] **Step 6: Verify the project file is still valid and the app still builds**

Run: `plutil -lint Readiness.xcodeproj/project.pbxproj`
Expected: `OK`

Run: `xcodebuild -project Readiness.xcodeproj -scheme Readiness -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build`
Expected: exit 0, no output.

- [ ] **Step 7: Commit**

```bash
git add Core/Sources/ReadinessCore/NotificationMoment.swift Core/Tests/ReadinessCoreTests/NotificationMomentTests.swift Readiness.xcodeproj/project.pbxproj
git commit -m "The moments Jett can initiate, and which ones cost him"
```

---

### Task 2: The speaking budget — `NotificationBudget`

**Files:**
- Create: `Core/Sources/ReadinessCore/NotificationBudget.swift`
- Modify: `Readiness.xcodeproj/project.pbxproj`
- Test: `Core/Tests/ReadinessCoreTests/NotificationBudgetTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `public enum NotificationBudget` with `static let capacity = 3`, `static let refillInterval: TimeInterval = 48 * 3600`, `struct State: Equatable, Sendable, Codable` (`init()`, `init(tokens: Double, updated: Date?)`), `struct Decision: Equatable, Sendable` (`allowed: Bool`, `state: State`), and `static func consume(_ state: State, now: Date) -> Decision`.

**Note on the deliberate duplication:** this is the same token-bucket arithmetic as `BurstLimiter`, with different constants. `BurstLimiter` is not generalised or modified because the coach path depends on it and this change must not be able to break a paying user's conversation. Twenty-five lines of duplication is the cheaper risk. The backwards-clock guard is duplicated too, and Step 1 pins it with its own test so the two cannot drift silently.

- [ ] **Step 1: Write the failing test**

Create `Core/Tests/ReadinessCoreTests/NotificationBudgetTests.swift`:

```swift
import Testing
import Foundation
@testable import ReadinessCore

/// Jett has three coins and earns one every two days. An eventful day can spend two or
/// three; doing that leaves him quiet for a while. A weekly counter was rejected because
/// it cannot tell four-across-a-week from four-on-Monday.
@Suite("The speaking budget")
struct NotificationBudgetTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a fresh bucket allows a whole day's burst")
    func burstIsAllowed() {
        var state = NotificationBudget.State()
        for i in 0..<NotificationBudget.capacity {
            let result = NotificationBudget.consume(state, now: start)
            #expect(result.allowed, "refused message \(i + 1) of a fresh burst")
            state = result.state
        }
    }

    @Test("one more in the same instant is refused")
    func burstThenRefusal() {
        var state = NotificationBudget.State()
        for _ in 0..<NotificationBudget.capacity {
            state = NotificationBudget.consume(state, now: start).state
        }
        #expect(!NotificationBudget.consume(state, now: start).allowed)
    }

    @Test("two days of waiting earns exactly one back")
    func refill() {
        var state = NotificationBudget.State()
        for _ in 0..<NotificationBudget.capacity {
            state = NotificationBudget.consume(state, now: start).state
        }
        let later = start.addingTimeInterval(NotificationBudget.refillInterval)
        let first = NotificationBudget.consume(state, now: later)
        #expect(first.allowed)
        #expect(!NotificationBudget.consume(first.state, now: later).allowed)
    }

    @Test("a quiet fortnight does not bank more than the bucket holds")
    func doesNotOverfill() {
        var state = NotificationBudget.State()
        state = NotificationBudget.consume(state, now: start).state
        let fortnight = start.addingTimeInterval(14 * 24 * 3600)
        for i in 0..<NotificationBudget.capacity {
            let result = NotificationBudget.consume(state, now: fortnight)
            #expect(result.allowed, "refused message \(i + 1) after a quiet fortnight")
            state = result.state
        }
        #expect(!NotificationBudget.consume(state, now: fortnight).allowed)
    }

    @Test("winding the clock back does not refill the bucket")
    func clockGoingBackwardsEarnsNothing() {
        var state = NotificationBudget.State()
        for _ in 0..<NotificationBudget.capacity {
            state = NotificationBudget.consume(state, now: start).state
        }
        let yesterday = start.addingTimeInterval(-100 * 24 * 3600)
        #expect(!NotificationBudget.consume(state, now: yesterday).allowed)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NotificationBudgetTests`
Expected: FAIL — `cannot find 'NotificationBudget' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Core/Sources/ReadinessCore/NotificationBudget.swift`:

```swift
import Foundation

/// A token bucket over the messages Jett initiates.
///
/// The jar holds three coins and one drops in every two days. A day worth talking about
/// can spend two or three; doing that leaves him genuinely quiet for the next few days,
/// which is the behaviour wanted. Sustained, it settles around three or four a week.
///
/// A weekly cap was considered and rejected: it cannot distinguish four messages spread
/// across a week from four on Monday, and it resets on an arbitrary boundary, so someone
/// who spends the allowance by Saturday is mute until midnight Sunday and then has a full
/// allowance again. A bucket has no boundary — it just makes a busy day cost something.
///
/// This is `BurstLimiter`'s arithmetic with different constants, deliberately copied
/// rather than shared. `BurstLimiter` guards a paying user's conversation with the coach,
/// and no notification change should be able to reach it.
public enum NotificationBudget {

    /// How many budgeted messages can go out close together on one eventful day.
    public static let capacity = 3

    /// Seconds to earn one back. Two days, which sets the long-run average.
    public static let refillInterval: TimeInterval = 48 * 60 * 60

    public struct State: Equatable, Sendable, Codable {
        var tokens: Double
        var updated: Date?

        public init() {
            tokens = Double(NotificationBudget.capacity)
            updated = nil
        }

        public init(tokens: Double, updated: Date?) {
            self.tokens = tokens
            self.updated = updated
        }
    }

    public struct Decision: Equatable, Sendable {
        public let allowed: Bool
        public let state: State
    }

    public static func consume(_ state: State, now: Date) -> Decision {
        var tokens = state.tokens

        if let updated = state.updated {
            // Device clocks move, including backwards. Treating a negative interval as
            // elapsed time would let anyone refill the bucket by changing the date.
            let elapsed = max(0, now.timeIntervalSince(updated))
            tokens = min(Double(capacity), tokens + elapsed / refillInterval)
        }

        guard tokens >= 1 else {
            return Decision(allowed: false, state: State(tokens: tokens, updated: now))
        }
        return Decision(allowed: true, state: State(tokens: tokens - 1, updated: now))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NotificationBudgetTests`
Expected: PASS, 5 tests.

- [ ] **Step 5: Register the file in the app target**

Same four `project.pbxproj` edits as Task 1 Step 5, with two fresh unique 24-char hex IDs, for `NotificationBudget.swift`.

- [ ] **Step 6: Verify**

Run: `plutil -lint Readiness.xcodeproj/project.pbxproj` → `OK`
Run: `xcodebuild -project Readiness.xcodeproj -scheme Readiness -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build` → exit 0

- [ ] **Step 7: Commit**

```bash
git add Core/Sources/ReadinessCore/NotificationBudget.swift Core/Tests/ReadinessCoreTests/NotificationBudgetTests.swift Readiness.xcodeproj/project.pbxproj
git commit -m "Three coins in the jar, one back every two days"
```

---

### Task 3: What was already said — `NotificationRecord`

**Files:**
- Create: `Core/Sources/ReadinessCore/NotificationRecord.swift`
- Modify: `Readiness.xcodeproj/project.pbxproj`
- Test: `Core/Tests/ReadinessCoreTests/NotificationRecordTests.swift`

**Interfaces:**
- Consumes: `NotificationBudget.State` (Task 2), `NotificationMoment` (Task 1).
- Produces: `public struct NotificationRecord: Equatable, Sendable, Codable` with `var lastMorningVerdict: Date?`, `var lastIllnessGate: Date?`, `var lastBedtimeTarget: Date?`, `var lastInsight: String?`, `var budget: NotificationBudget.State`, `init()`, and `func alreadySentToday(_ moment: NotificationMoment, now: Date, calendar: Calendar) -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `Core/Tests/ReadinessCoreTests/NotificationRecordTests.swift`:

```swift
import Testing
import Foundation
@testable import ReadinessCore

/// The engine is a pure function, so everything it remembers has to be handed to it.
@Suite("What Jett remembers saying")
struct NotificationRecordTests {

    /// Pinned to UTC. These tests assert what falls on the same day, and an unpinned
    /// calendar makes the answer depend on where the machine running them is.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let morning = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a fresh record has said nothing and has a full bucket")
    func freshRecord() {
        let record = NotificationRecord()
        #expect(record.lastMorningVerdict == nil)
        #expect(record.lastInsight == nil)
        #expect(!record.alreadySentToday(.morningVerdict, now: morning, calendar: calendar))
        #expect(NotificationBudget.consume(record.budget, now: morning).allowed)
    }

    @Test("a verdict sent this morning blocks another this afternoon")
    func sameDayIsBlocked() {
        var record = NotificationRecord()
        record.lastMorningVerdict = morning
        let afternoon = morning.addingTimeInterval(8 * 3600)
        #expect(record.alreadySentToday(.morningVerdict, now: afternoon, calendar: calendar))
    }

    @Test("a verdict sent yesterday does not block today's")
    func yesterdayDoesNotBlock() {
        var record = NotificationRecord()
        record.lastMorningVerdict = morning
        let tomorrow = morning.addingTimeInterval(24 * 3600)
        #expect(!record.alreadySentToday(.morningVerdict, now: tomorrow, calendar: calendar))
    }

    @Test("each moment is tracked separately")
    func momentsAreIndependent() {
        var record = NotificationRecord()
        record.lastMorningVerdict = morning
        #expect(record.alreadySentToday(.morningVerdict, now: morning, calendar: calendar))
        #expect(!record.alreadySentToday(.illnessGate, now: morning, calendar: calendar))
        #expect(!record.alreadySentToday(.bedtimeTarget, now: morning, calendar: calendar))
    }

    @Test("an insight is remembered by its words, not its day")
    func insightIsTextual() {
        var record = NotificationRecord()
        record.lastInsight = "Your training volume has been about 18% higher."
        // Novelty for insights is a text comparison; the day-based check never blocks it.
        #expect(!record.alreadySentToday(.newInsight, now: morning, calendar: calendar))
    }

    @Test("it survives a round trip through JSON")
    func codable() throws {
        var record = NotificationRecord()
        record.lastMorningVerdict = morning
        record.lastInsight = "something"
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(NotificationRecord.self, from: data) == record)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NotificationRecordTests`
Expected: FAIL — `cannot find 'NotificationRecord' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Core/Sources/ReadinessCore/NotificationRecord.swift`:

```swift
import Foundation

/// Everything the decision needs to know about what has already been said.
///
/// The engine is a pure function, so it cannot look anything up. The app persists this
/// between launches and hands it back on the next decision.
public struct NotificationRecord: Equatable, Sendable, Codable {

    public var lastMorningVerdict: Date?
    public var lastIllnessGate: Date?
    public var lastBedtimeTarget: Date?
    /// The exact words last sent, because insight novelty is a text comparison rather
    /// than a calendar one — a finding that has not changed is not news, however long ago
    /// it was first said.
    public var lastInsight: String?
    public var budget: NotificationBudget.State

    public init() {
        budget = NotificationBudget.State()
    }

    /// Whether this moment has already gone out on the day `now` falls in.
    ///
    /// Always false for `.newInsight`: that moment is bounded by its own words, not by
    /// the calendar, and a day-based block would be a second rule doing nothing.
    public func alreadySentToday(_ moment: NotificationMoment, now: Date,
                                 calendar: Calendar = .current) -> Bool {
        let last: Date?
        switch moment {
        case .morningVerdict: last = lastMorningVerdict
        case .illnessGate: last = lastIllnessGate
        case .bedtimeTarget: last = lastBedtimeTarget
        case .newInsight: return false
        }
        guard let last else { return false }
        return calendar.isDate(last, inSameDayAs: now)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NotificationRecordTests`
Expected: PASS, 6 tests.

- [ ] **Step 5: Register the file in the app target**

Same four `project.pbxproj` edits, fresh unique IDs, for `NotificationRecord.swift`.

- [ ] **Step 6: Verify**

Run: `plutil -lint Readiness.xcodeproj/project.pbxproj` → `OK`
Run: `xcodebuild -project Readiness.xcodeproj -scheme Readiness -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build` → exit 0

- [ ] **Step 7: Commit**

```bash
git add Core/Sources/ReadinessCore/NotificationRecord.swift Core/Tests/ReadinessCoreTests/NotificationRecordTests.swift Readiness.xcodeproj/project.pbxproj
git commit -m "What Jett remembers having said"
```

---

### Task 4: The morning verdict

**Files:**
- Create: `Core/Sources/ReadinessCore/MorningVerdict.swift`
- Modify: `Readiness.xcodeproj/project.pbxproj`
- Test: `Core/Tests/ReadinessCoreTests/MorningVerdictTests.swift`

**Interfaces:**
- Consumes: `SignalScore`, `ScoreContributor`, `ScoreCoverage` (existing, `Core/Sources/ReadinessCore/SignalScore.swift`).
- Produces: `public enum MorningVerdict` with `static let notableForInterruption = 5.0`, `static let minimumHistoryForBest = 14`, `static let bestWindow = 21`, and `static func sentence(recovery: SignalScore, sleep: SignalScore, recentSleepScores: [Double]) -> String?`.

**The rule, from the spec:** fire on bad nights, and on exceptional good ones. A bad morning is one where the leading contributor of *either* the recovery or the sleep score moved it down by at least `notableForInterruption` points; the sentence comes from whichever moved further, because the night that felt fine and had no deep sleep shows up in sleep while HRV stays clean. An exceptional morning is a sleep score strictly better than every one of the last `bestWindow` nights, with at least `minimumHistoryForBest` nights to judge against. Everything else returns nil and the widget carries it.

- [ ] **Step 1: Write the failing test**

Create `Core/Tests/ReadinessCoreTests/MorningVerdictTests.swift`:

```swift
import Testing
import Foundation
@testable import ReadinessCore

/// The morning verdict is the app's core output. It is not budgeted, and it is not
/// suppressed for repeating itself — a fifth consecutive rough night is a fifth day the
/// user should train differently.
@Suite("The morning verdict")
struct MorningVerdictTests {

    /// A score with one contributor that moved it by `magnitude` points.
    private func score(_ kind: SignalKind, value: Double, magnitude: Double,
                       coverage: ScoreCoverage = .full) -> SignalScore {
        SignalScore(
            kind: kind, value: value, band: nil,
            contributors: [ScoreContributor(
                id: "hrv", title: "Heart rate variability", value: 42, unit: "ms",
                comparison: 58, comparisonLabel: "your normal", state: .payAttention,
                magnitude: magnitude, explanation: "")],
            coverage: coverage, neutral: 50, modelVersion: "test")
    }

    private func flatScore(_ kind: SignalKind, value: Double) -> SignalScore {
        score(kind, value: value, magnitude: 0.4)
    }

    /// Above every "ordinary" fixture below (80, 88) and below the 96 the exceptional
    /// tests use. A history beneath the ordinary values would make every silent morning
    /// a personal best.
    private let ordinaryHistory = Array(repeating: 94.0, count: 21)

    @Test("a night that pulled the score well down speaks")
    func badNightSpeaks() {
        let sentence = MorningVerdict.sentence(
            recovery: score(.recovery, value: 44, magnitude: -9),
            sleep: flatScore(.sleep, value: 80),
            recentSleepScores: ordinaryHistory)
        #expect(sentence != nil)
    }

    @Test("a night nothing stood out in stays quiet")
    func unremarkableNightIsSilent() {
        #expect(MorningVerdict.sentence(
            recovery: flatScore(.recovery, value: 72),
            sleep: flatScore(.sleep, value: 80),
            recentSleepScores: ordinaryHistory) == nil)
    }

    @Test("worth saying on screen is not yet worth a lock screen")
    func screenBarIsNotTheInterruptionBar() {
        // 3 points clears SignalScore.notableMagnitude (2.0) and not
        // MorningVerdict.notableForInterruption (5.0).
        #expect(SignalScore.notableMagnitude < 3.0)
        #expect(MorningVerdict.notableForInterruption > 3.0)
        #expect(MorningVerdict.sentence(
            recovery: score(.recovery, value: 64, magnitude: -3),
            sleep: flatScore(.sleep, value: 80),
            recentSleepScores: ordinaryHistory) == nil)
    }

    @Test("a bad night shows up through sleep even when recovery is clean")
    func sleepCanCarryTheNews() {
        let sentence = MorningVerdict.sentence(
            recovery: flatScore(.recovery, value: 71),
            sleep: score(.sleep, value: 58, magnitude: -11),
            recentSleepScores: ordinaryHistory)
        #expect(sentence != nil)
    }

    @Test("the sentence comes from whichever signal moved further")
    func worseSignalWins() {
        let sentence = MorningVerdict.sentence(
            recovery: score(.recovery, value: 55, magnitude: -6),
            sleep: score(.sleep, value: 40, magnitude: -14),
            recentSleepScores: ordinaryHistory)
        let expected = score(.sleep, value: 40, magnitude: -14).summary
        #expect(sentence == expected)
    }

    @Test("an ordinary good night stays quiet")
    func goodNightIsSilent() {
        #expect(MorningVerdict.sentence(
            recovery: score(.recovery, value: 82, magnitude: 8),
            sleep: score(.sleep, value: 88, magnitude: 6),
            recentSleepScores: ordinaryHistory) == nil)
    }

    @Test("a genuine three-week best speaks")
    func exceptionalNightSpeaks() {
        let sentence = MorningVerdict.sentence(
            recovery: score(.recovery, value: 82, magnitude: 8),
            sleep: score(.sleep, value: 96, magnitude: 6),
            recentSleepScores: ordinaryHistory)
        #expect(sentence == "Your best night in three weeks.")
    }

    @Test("a best is not claimed without enough nights to claim it against")
    func thinHistoryClaimsNothing() {
        #expect(MorningVerdict.sentence(
            recovery: score(.recovery, value: 82, magnitude: 8),
            sleep: score(.sleep, value: 96, magnitude: 6),
            recentSleepScores: Array(repeating: 94.0, count: 5)) == nil)
    }

    @Test("a best claims only the weeks it actually beat")
    func bestNamesTheRealWindow() {
        let sentence = MorningVerdict.sentence(
            recovery: score(.recovery, value: 82, magnitude: 8),
            sleep: score(.sleep, value: 96, magnitude: 6),
            recentSleepScores: Array(repeating: 94.0, count: 14))
        #expect(sentence == "Your best night in two weeks.")
    }

    @Test("a score the app does not have says nothing")
    func unavailableIsSilent() {
        let missing = SignalScore(kind: .sleep, value: nil, band: nil, contributors: [],
                                  coverage: .unavailable, modelVersion: "test")
        #expect(MorningVerdict.sentence(
            recovery: missing, sleep: missing,
            recentSleepScores: ordinaryHistory) == nil)
    }

    @Test("bad news outranks a best, on the morning that manages both")
    func badNewsWins() {
        let sentence = MorningVerdict.sentence(
            recovery: score(.recovery, value: 38, magnitude: -12),
            sleep: score(.sleep, value: 96, magnitude: 6),
            recentSleepScores: ordinaryHistory)
        #expect(sentence != "Your best night in three weeks.")
        #expect(sentence != nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MorningVerdictTests`
Expected: FAIL — `cannot find 'MorningVerdict' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Core/Sources/ReadinessCore/MorningVerdict.swift`:

```swift
import Foundation

/// Whether this morning is worth a lock screen, and what it says if it is.
///
/// The app's core output, so it is never budgeted and never suppressed for repeating
/// itself. What produces silence is the morning having nothing to report.
public enum MorningVerdict {

    /// How far a contributor must have moved a score before interrupting for it.
    ///
    /// `SignalScore.notableMagnitude` (2.0) is the bar for text sitting next to the
    /// number, where the reader has already chosen to look. A lock screen costs more.
    public static let notableForInterruption = 5.0

    /// Nights of history needed before "a best" is a claim rather than an accident.
    public static let minimumHistoryForBest = 14

    /// How far back a best has to reach.
    public static let bestWindow = 21

    /// The sentence to send, or nil when this morning is not worth interrupting for.
    public static func sentence(recovery: SignalScore, sleep: SignalScore,
                                recentSleepScores: [Double]) -> String? {
        if let bad = worstNews(recovery: recovery, sleep: sleep) { return bad.summary }
        return bestNight(sleep: sleep, recent: recentSleepScores)
    }

    /// Whichever signal moved furthest down, provided it moved far enough to interrupt.
    ///
    /// Both are read, not just recovery: the night that felt fine and had almost no deep
    /// sleep shows up in the sleep score while HRV stays perfectly clean, and that is
    /// exactly the morning worth catching.
    private static func worstNews(recovery: SignalScore, sleep: SignalScore) -> SignalScore? {
        [recovery, sleep]
            .filter { $0.coverage != .unavailable }
            .filter { ($0.contributors.first?.magnitude ?? 0) <= -notableForInterruption }
            .min { ($0.contributors.first?.magnitude ?? 0) < ($1.contributors.first?.magnitude ?? 0) }
    }

    /// A night better than every one it can be compared against.
    ///
    /// Ordinary good nights are the widget's job. This fires only for something the user
    /// would want to be told, which by construction is rare.
    private static func bestNight(sleep: SignalScore, recent: [Double]) -> String? {
        guard sleep.coverage != .unavailable, let value = sleep.value else { return nil }
        let window = Array(recent.suffix(bestWindow))
        guard window.count >= minimumHistoryForBest,
              let best = window.max(), value > best else { return nil }
        return "Your best night in \(weeks(window.count)) weeks."
    }

    /// Named for what it actually beat. Claiming three weeks off fourteen nights is a
    /// small lie, and the one place the app cannot afford small lies is the lock screen.
    private static func weeks(_ nights: Int) -> String {
        switch nights / 7 {
        case ..<3: return "two"
        default: return "three"
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MorningVerdictTests`
Expected: PASS, 11 tests.

- [ ] **Step 5: Register the file in the app target**

Same four `project.pbxproj` edits, fresh unique IDs, for `MorningVerdict.swift`.

- [ ] **Step 6: Verify**

Run: `plutil -lint Readiness.xcodeproj/project.pbxproj` → `OK`
Run: `xcodebuild -project Readiness.xcodeproj -scheme Readiness -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build` → exit 0

- [ ] **Step 7: Commit**

```bash
git add Core/Sources/ReadinessCore/MorningVerdict.swift Core/Tests/ReadinessCoreTests/MorningVerdictTests.swift Readiness.xcodeproj/project.pbxproj
git commit -m "A morning speaks when the night gave it something to say"
```

---

### Task 5: The bedtime target

**Files:**
- Create: `Core/Sources/ReadinessCore/BedtimeTarget.swift`
- Modify: `Readiness.xcodeproj/project.pbxproj`
- Test: `Core/Tests/ReadinessCoreTests/BedtimeTargetTests.swift`

**Interfaces:**
- Consumes: `SleepNeed` (existing, `Core/Sources/ReadinessCore/SleepScore.swift` — fields `hours`, `baseline`, `debt`, `strainAdjustment`, `napCredit`).
- Produces: `public enum BedtimeTarget` with `static let unusualMarginHours = 0.75`, `static let windowMinutes = 90.0`, `static func isDue(now: Date, usualBedtime: Date) -> Bool`, `static func sentence(need: SleepNeed) -> String?`.

**The rule, from the spec:** the only moment that changes an outcome rather than reporting one. Fires in the ninety minutes before the user's usual bedtime, and only when tonight's need exceeds their own baseline by `unusualMarginHours` or more. The reason named is whichever of yesterday's strain or accumulated debt contributed more.

- [ ] **Step 1: Write the failing test**

Create `Core/Tests/ReadinessCoreTests/BedtimeTargetTests.swift`:

```swift
import Testing
import Foundation
@testable import ReadinessCore

/// The one message that can change tonight instead of describing last night.
@Suite("The bedtime target")
struct BedtimeTargetTests {

    private let bedtime = Date(timeIntervalSince1970: 1_800_000_000)

    private func need(hours: Double, debt: Double = 0, strain: Double = 0) -> SleepNeed {
        SleepNeed(hours: hours, baseline: SleepNeed.baselineHours,
                  debt: debt, strainAdjustment: strain, napCredit: 0)
    }

    @Test("an hour before bed is inside the window")
    func withinWindow() {
        #expect(BedtimeTarget.isDue(now: bedtime.addingTimeInterval(-60 * 60),
                                    usualBedtime: bedtime))
    }

    @Test("the whole afternoon is not")
    func tooEarly() {
        #expect(!BedtimeTarget.isDue(now: bedtime.addingTimeInterval(-5 * 3600),
                                     usualBedtime: bedtime))
    }

    @Test("after bedtime is too late to be useful")
    func tooLate() {
        #expect(!BedtimeTarget.isDue(now: bedtime.addingTimeInterval(30 * 60),
                                     usualBedtime: bedtime))
    }

    @Test("an ordinary night says nothing")
    func ordinaryNightIsSilent() {
        #expect(BedtimeTarget.sentence(need: need(hours: 8.1)) == nil)
    }

    @Test("a hard day asks for more, and says why")
    func hardDaySpeaks() {
        let sentence = BedtimeTarget.sentence(
            need: need(hours: 8.75, debt: 0.1, strain: 0.7))
        #expect(sentence?.contains("8.75") == true || sentence?.contains("8.8") == true)
        #expect(sentence?.lowercased().contains("yesterday") == true)
    }

    @Test("accumulated debt asks for more, and says that instead")
    func debtSpeaks() {
        let sentence = BedtimeTarget.sentence(
            need: need(hours: 8.8, debt: 1.4, strain: 0.05))
        #expect(sentence?.lowercased().contains("behind") == true)
    }

    @Test("the margin is a threshold, not a suggestion")
    func justUnderTheMarginIsSilent() {
        let hours = SleepNeed.baselineHours + BedtimeTarget.unusualMarginHours - 0.01
        #expect(BedtimeTarget.sentence(need: need(hours: hours, strain: 0.7)) == nil)
    }

    @Test("exactly on the margin speaks")
    func onTheMarginSpeaks() {
        let hours = SleepNeed.baselineHours + BedtimeTarget.unusualMarginHours
        #expect(BedtimeTarget.sentence(need: need(hours: hours, strain: 0.7)) != nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BedtimeTargetTests`
Expected: FAIL — `cannot find 'BedtimeTarget' in scope`. It may also fail on `SleepNeed`'s memberwise initialiser not being public.

- [ ] **Step 3: Make `SleepNeed`'s initialiser available to tests if it is not already**

`SleepNeed` is built by `SleepNeed.of(...)` and may have only an implicit internal memberwise init. The test target uses `@testable import ReadinessCore`, so an internal init is reachable and no change is needed. If the compiler disagrees, add this to `SleepNeed` in `Core/Sources/ReadinessCore/SleepScore.swift` and nothing else:

```swift
    init(hours: Double, baseline: Double, debt: Double,
         strainAdjustment: Double, napCredit: Double) {
        self.hours = hours
        self.baseline = baseline
        self.debt = debt
        self.strainAdjustment = strainAdjustment
        self.napCredit = napCredit
    }
```

- [ ] **Step 4: Write minimal implementation**

Create `Core/Sources/ReadinessCore/BedtimeTarget.swift`:

```swift
import Foundation

/// What tonight has to be, said while there is still time to do something about it.
///
/// Every other message describes data already fixed — a morning verdict is about a night
/// that cannot be changed. This one is the exception, which is why it is worth the
/// interruption on the nights it fires.
public enum BedtimeTarget {

    /// How far above their own baseline tonight has to be before it is worth saying.
    /// Below this the widget carries it.
    public static let unusualMarginHours = 0.75

    /// How long before the usual bedtime the message may go out.
    public static let windowMinutes = 90.0

    /// Whether now is inside the window before tonight's usual bedtime.
    ///
    /// Bounded on both sides: a target delivered after bedtime is a reproach rather than
    /// a plan, and one delivered at teatime will have been forgotten.
    public static func isDue(now: Date, usualBedtime: Date) -> Bool {
        let secondsUntil = usualBedtime.timeIntervalSince(now)
        return secondsUntil > 0 && secondsUntil <= windowMinutes * 60
    }

    /// The sentence to send, or nil when tonight is an ordinary night.
    public static func sentence(need: SleepNeed) -> String? {
        guard need.hours - need.baseline >= unusualMarginHours else { return nil }
        let hours = need.hours.formatted(.number.precision(.fractionLength(0...1)))
        // Whichever of the two actually drove it. Naming the smaller one would be the
        // app explaining itself with the wrong reason.
        let because = need.strainAdjustment >= need.debt * SleepNeed.repaymentFraction
            ? "Yesterday was hard"
            : "You are behind on sleep"
        return "\(because) — tonight needs about \(hours) hours."
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter BedtimeTargetTests`
Expected: PASS, 8 tests.

- [ ] **Step 6: Register the file in the app target**

Same four `project.pbxproj` edits, fresh unique IDs, for `BedtimeTarget.swift`.

- [ ] **Step 7: Verify**

Run: `plutil -lint Readiness.xcodeproj/project.pbxproj` → `OK`
Run: `xcodebuild -project Readiness.xcodeproj -scheme Readiness -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build` → exit 0

- [ ] **Step 8: Commit**

```bash
git add Core/Sources/ReadinessCore/BedtimeTarget.swift Core/Tests/ReadinessCoreTests/BedtimeTargetTests.swift Readiness.xcodeproj/project.pbxproj
git commit -m "The one message that can still change tonight"
```

---

### Task 6: The decision — `NotificationDecision`

**Files:**
- Create: `Core/Sources/ReadinessCore/NotificationDecision.swift`
- Modify: `Readiness.xcodeproj/project.pbxproj`
- Test: `Core/Tests/ReadinessCoreTests/NotificationDecisionTests.swift`

**Interfaces:**
- Consumes: `NotificationMoment` (Task 1), `NotificationBudget` (Task 2), `NotificationRecord` (Task 3), `MorningVerdict` (Task 4), `BedtimeTarget` (Task 5), plus existing `SignalScore`, `ReadinessGate`, `SleepNeed`.
- Produces: `public enum NotificationDecision` with nested `public struct Input: Sendable`, `public struct Outcome: Equatable, Sendable` (`moment`, `body`, `record`), and `public static func next(_ input: Input) -> Outcome?`.

**Priority order, highest first:** illness gate, morning verdict, bedtime target, new insight. The gate outranks everything because it is the one thing the app may know before the user does and the one harm it exists to prevent. Budgeted moments consume a token only when they are actually chosen; a moment that was going to be skipped anyway must not cost one.

- [ ] **Step 1: Write the failing test**

Create `Core/Tests/ReadinessCoreTests/NotificationDecisionTests.swift`:

```swift
import Testing
import Foundation
@testable import ReadinessCore

/// The whole rule, end to end: which moment wins, what silences it, and what a message
/// costs.
@Suite("Deciding whether Jett speaks")
struct NotificationDecisionTests {

    /// Pinned to UTC, for the same reason as `NotificationRecordTests`: `morningThenBedtime`
    /// puts thirteen and a half hours between two instants and asserts they are the same
    /// day, which is false east of about UTC+3 under the system calendar.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    private let morning = Date(timeIntervalSince1970: 1_800_000_000)

    private func score(_ kind: SignalKind, value: Double, magnitude: Double,
                       gate: ReadinessGate? = nil) -> SignalScore {
        SignalScore(
            kind: kind, value: value, band: nil,
            contributors: [ScoreContributor(
                id: "hrv", title: "Heart rate variability", value: 42, unit: "ms",
                comparison: 58, comparisonLabel: "your normal", state: .payAttention,
                magnitude: magnitude, explanation: "")],
            coverage: .full, neutral: 50, gate: gate, modelVersion: "test")
    }

    private func input(
        now: Date? = nil,
        recovery: SignalScore? = nil,
        sleep: SignalScore? = nil,
        // Above the default sleep fixture (80), so an ordinary morning is not silently
        // a personal best and the silence tests below test what they claim to.
        recentSleepScores: [Double] = Array(repeating: 94.0, count: 21),
        tonightsNeed: SleepNeed? = nil,
        usualBedtime: Date? = nil,
        insight: String? = nil,
        record: NotificationRecord = NotificationRecord()
    ) -> NotificationDecision.Input {
        NotificationDecision.Input(
            now: now ?? morning,
            recovery: recovery ?? score(.recovery, value: 72, magnitude: 0.4),
            sleep: sleep ?? score(.sleep, value: 80, magnitude: 0.4),
            recentSleepScores: recentSleepScores,
            tonightsNeed: tonightsNeed,
            usualBedtime: usualBedtime,
            insight: insight,
            record: record,
            calendar: calendar)
    }

    @Test("an ordinary morning with nothing else going on says nothing")
    func quietMorning() {
        #expect(NotificationDecision.next(input()) == nil)
    }

    @Test("a bad morning produces the verdict")
    func badMorning() {
        let outcome = NotificationDecision.next(
            input(recovery: score(.recovery, value: 41, magnitude: -11)))
        #expect(outcome?.moment == .morningVerdict)
    }

    @Test("the illness gate outranks the morning verdict")
    func gateWins() {
        let outcome = NotificationDecision.next(
            input(recovery: score(.recovery, value: 8, magnitude: -30,
                                  gate: .elevatedWristTemperature)))
        #expect(outcome?.moment == .illnessGate)
    }

    @Test("a load spike is not the illness gate")
    func loadSpikeIsNotIllness() {
        let outcome = NotificationDecision.next(
            input(recovery: score(.recovery, value: 60, magnitude: -11,
                                  gate: .acuteLoadSpike)))
        #expect(outcome?.moment == .morningVerdict)
    }

    @Test("the verdict goes out once a day, however often the app refreshes")
    func onePerDay() {
        var record = NotificationRecord()
        record.lastMorningVerdict = morning
        let outcome = NotificationDecision.next(input(
            now: morning.addingTimeInterval(4 * 3600),
            recovery: score(.recovery, value: 41, magnitude: -11),
            record: record))
        #expect(outcome == nil)
    }

    @Test("the same news the next day goes out again — novelty does not gate the verdict")
    func repeatsAcrossDays() {
        var record = NotificationRecord()
        record.lastMorningVerdict = morning
        let outcome = NotificationDecision.next(input(
            now: morning.addingTimeInterval(24 * 3600),
            recovery: score(.recovery, value: 41, magnitude: -11),
            record: record))
        #expect(outcome?.moment == .morningVerdict)
    }

    @Test("an empty bucket cannot silence the verdict or the gate")
    func exemptMomentsIgnoreTheBucket() {
        var record = NotificationRecord()
        record.budget = NotificationBudget.State(tokens: 0, updated: morning)
        #expect(NotificationDecision.next(input(
            recovery: score(.recovery, value: 41, magnitude: -11),
            record: record))?.moment == .morningVerdict)
        #expect(NotificationDecision.next(input(
            recovery: score(.recovery, value: 8, magnitude: -30,
                            gate: .elevatedWristTemperature),
            record: record))?.moment == .illnessGate)
    }

    @Test("an empty bucket does silence an insight")
    func bucketSilencesInsight() {
        var record = NotificationRecord()
        record.budget = NotificationBudget.State(tokens: 0, updated: morning)
        #expect(NotificationDecision.next(input(insight: "Something true.",
                                                record: record)) == nil)
    }

    @Test("an insight that has already been said is not news")
    func insightNovelty() {
        var record = NotificationRecord()
        record.lastInsight = "Something true."
        #expect(NotificationDecision.next(input(insight: "Something true.",
                                                record: record)) == nil)
    }

    @Test("a new insight speaks and is remembered")
    func newInsightSpeaks() {
        let outcome = NotificationDecision.next(input(insight: "Something new."))
        #expect(outcome?.moment == .newInsight)
        #expect(outcome?.record.lastInsight == "Something new.")
    }

    @Test("a bedtime target speaks in its window and spends a coin")
    func bedtimeSpeaks() {
        let bedtime = morning.addingTimeInterval(14 * 3600)
        let now = bedtime.addingTimeInterval(-30 * 60)
        let outcome = NotificationDecision.next(input(
            now: now,
            tonightsNeed: SleepNeed(hours: 8.9, baseline: 8.0, debt: 0.2,
                                    strainAdjustment: 0.7, napCredit: 0),
            usualBedtime: bedtime))
        #expect(outcome?.moment == .bedtimeTarget)

        // A full jar minus this message leaves exactly capacity - 1 more in the instant,
        // which is what "it spent a coin" means.
        var left = 0
        var state = outcome!.record.budget
        while NotificationBudget.consume(state, now: now).allowed {
            state = NotificationBudget.consume(state, now: now).state
            left += 1
        }
        #expect(left == NotificationBudget.capacity - 1)
    }

    @Test("a quiet day leaves the whole allowance for the day that needs it")
    func skippedMomentsAreFree() {
        // A hundred quiet decisions in a row, then one real insight. If a skipped
        // moment ever cost a coin, the jar would be empty long before the news arrived.
        var record = NotificationRecord()
        for _ in 0..<100 {
            #expect(NotificationDecision.next(input(record: record)) == nil)
        }
        record = NotificationRecord()
        let outcome = NotificationDecision.next(input(insight: "Something new.",
                                                      record: record))
        #expect(outcome?.moment == .newInsight)
    }

    @Test("a morning outranks a bedtime target, and the bedtime still comes that evening")
    func morningThenBedtime() {
        let bedtime = morning.addingTimeInterval(14 * 3600)
        let need = SleepNeed(hours: 8.9, baseline: 8.0, debt: 0.2,
                             strainAdjustment: 0.7, napCredit: 0)
        let first = NotificationDecision.next(input(
            recovery: score(.recovery, value: 41, magnitude: -11),
            tonightsNeed: need, usualBedtime: bedtime))
        #expect(first?.moment == .morningVerdict)

        let second = NotificationDecision.next(input(
            now: bedtime.addingTimeInterval(-30 * 60),
            recovery: score(.recovery, value: 41, magnitude: -11),
            tonightsNeed: need, usualBedtime: bedtime,
            record: first!.record))
        #expect(second?.moment == .bedtimeTarget)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter NotificationDecisionTests`
Expected: FAIL — `cannot find 'NotificationDecision' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Core/Sources/ReadinessCore/NotificationDecision.swift`:

```swift
import Foundation

/// Whether Coach Jett says anything right now, and what.
///
/// The whole product rule in one pure function: the app interrupts when it knows
/// something the user does not, that changes what they do today. Everything this returns
/// is decided here and merely delivered by the app layer, so every decision in
/// docs/superpowers/specs/2026-09-19-notifications-design.md is provable by `swift test`.
public enum NotificationDecision {

    public struct Input: Sendable {
        public let now: Date
        public let recovery: SignalScore
        public let sleep: SignalScore
        /// Sleep scores for the trailing nights, oldest first, excluding today.
        public let recentSleepScores: [Double]
        /// Nil when the app cannot work out what tonight needs.
        public let tonightsNeed: SleepNeed?
        /// Nil when there are not enough nights to know when this person goes to bed.
        public let usualBedtime: Date?
        public let insight: String?
        public let record: NotificationRecord
        public let calendar: Calendar

        public init(now: Date, recovery: SignalScore, sleep: SignalScore,
                    recentSleepScores: [Double] = [], tonightsNeed: SleepNeed? = nil,
                    usualBedtime: Date? = nil, insight: String? = nil,
                    record: NotificationRecord = NotificationRecord(),
                    calendar: Calendar = .current) {
            self.now = now
            self.recovery = recovery
            self.sleep = sleep
            self.recentSleepScores = recentSleepScores
            self.tonightsNeed = tonightsNeed
            self.usualBedtime = usualBedtime
            self.insight = insight
            self.record = record
            self.calendar = calendar
        }
    }

    public struct Outcome: Equatable, Sendable {
        public let moment: NotificationMoment
        public let body: String
        /// The record to persist, with this message written into it and any coin spent.
        public let record: NotificationRecord
    }

    /// Highest priority first. The gate leads because it is the one thing the app may
    /// know before the user does, and training hard into an illness is the concrete harm
    /// the app exists to prevent.
    public static func next(_ input: Input) -> Outcome? {
        if let outcome = illnessGate(input) { return outcome }
        if let outcome = morningVerdict(input) { return outcome }
        if let outcome = bedtimeTarget(input) { return outcome }
        return newInsight(input)
    }

    private static func illnessGate(_ input: Input) -> Outcome? {
        guard input.recovery.gate == .elevatedWristTemperature,
              !input.record.alreadySentToday(.illnessGate, now: input.now,
                                             calendar: input.calendar)
        else { return nil }
        var record = input.record
        record.lastIllnessGate = input.now
        return Outcome(moment: .illnessGate,
                       body: ReadinessGate.elevatedWristTemperature.explanation,
                       record: record)
    }

    private static func morningVerdict(_ input: Input) -> Outcome? {
        guard !input.record.alreadySentToday(.morningVerdict, now: input.now,
                                             calendar: input.calendar),
              let body = MorningVerdict.sentence(recovery: input.recovery,
                                                 sleep: input.sleep,
                                                 recentSleepScores: input.recentSleepScores)
        else { return nil }
        var record = input.record
        record.lastMorningVerdict = input.now
        return Outcome(moment: .morningVerdict, body: body, record: record)
    }

    private static func bedtimeTarget(_ input: Input) -> Outcome? {
        guard let need = input.tonightsNeed, let bedtime = input.usualBedtime,
              BedtimeTarget.isDue(now: input.now, usualBedtime: bedtime),
              !input.record.alreadySentToday(.bedtimeTarget, now: input.now,
                                             calendar: input.calendar),
              let body = BedtimeTarget.sentence(need: need)
        else { return nil }
        // The coin is spent last, so a moment that was going to be skipped anyway costs
        // nothing and the allowance survives for the day that needs it.
        guard var record = spend(input.record, now: input.now) else { return nil }
        record.lastBedtimeTarget = input.now
        return Outcome(moment: .bedtimeTarget, body: body, record: record)
    }

    private static func newInsight(_ input: Input) -> Outcome? {
        guard let insight = input.insight, !insight.isEmpty,
              insight != input.record.lastInsight
        else { return nil }
        guard var record = spend(input.record, now: input.now) else { return nil }
        record.lastInsight = insight
        return Outcome(moment: .newInsight, body: insight, record: record)
    }

    /// Nil when the bucket is empty, which is the whole of the refusal.
    private static func spend(_ record: NotificationRecord, now: Date) -> NotificationRecord? {
        let decision = NotificationBudget.consume(record.budget, now: now)
        guard decision.allowed else { return nil }
        var spent = record
        spent.budget = decision.state
        return spent
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter NotificationDecisionTests`
Expected: PASS, 13 tests.

- [ ] **Step 5: Run the whole suite to confirm nothing regressed**

Run: `swift test`
Expected: PASS. This plan adds 46 tests (3 + 5 + 6 + 11 + 8 + 13). The suite was 455 before it, so expect 501. If the pre-existing count differs, the number that matters is that **no previously passing test fails**.

- [ ] **Step 6: Register the file in the app target**

Same four `project.pbxproj` edits, fresh unique IDs, for `NotificationDecision.swift`.

- [ ] **Step 7: Verify**

Run: `plutil -lint Readiness.xcodeproj/project.pbxproj` → `OK`
Run: `xcodebuild -project Readiness.xcodeproj -scheme Readiness -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -quiet build` → exit 0

- [ ] **Step 8: Commit**

```bash
git add Core/Sources/ReadinessCore/NotificationDecision.swift Core/Tests/ReadinessCoreTests/NotificationDecisionTests.swift Readiness.xcodeproj/project.pbxproj
git commit -m "The whole rule, in one pure function"
```

---

## What this plan deliberately leaves out

These belong to later chunks and must not be built here:

- **`UNUserNotificationCenter`, categories, actions, permission flow.** Chunk 3.
- **Wake detection and the hold-until-06:00 rule.** Chunk 3 — it needs HealthKit observers. The engine takes `now` and answers for that instant; deciding *when* to ask is the app's job.
- **Quiet-hours preference storage.** Chunk 3.
- **The App Group snapshot and the widget.** Chunk 4.
- **The nap fix** (`SleepAggregator` summing naps into the wake-day bucket). Its own branch, blocked pending a reply from the `readiness-b9` session. It does not block this chunk: the engine consumes `SignalScore` values and is indifferent to how sleep duration was computed upstream.
- **Notification titles.** The engine returns a body only. Titles are a presentation concern and iOS already shows the app name; deciding whether a title earns its line is a chunk-3 question to answer against a real lock screen screenshot.
