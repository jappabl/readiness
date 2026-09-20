import SwiftUI
import SwiftData

@main
struct ReadinessApp: App {
    @State private var model = AppModel()
    @State private var store = Subscriptions()
    @State private var gym = GymPresence()
    @State private var appearance = Appearance()
    @Environment(\.scenePhase) private var scenePhase

    private let container = Store.container

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(store)
                .environment(gym)
                .environment(appearance)
                // Light by default, warm dark at night, or whatever they chose. The
                // system setting is deliberately not followed: iOS cannot tell us
                // whether it was chosen or inherited, so the preference is ours.
                .preferredColorScheme(appearance.isDark ? .dark : .light)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { appearance.refresh() }
                }
                .task { await store.load() }
                .task {
                    #if DEBUG
                    if let key = ProcessInfo.processInfo.environment["JETT_DEEPSEEK_API_KEY"], !key.isEmpty {
                        _ = MealPhotoKey.save(key)
                        unsetenv("JETT_DEEPSEEK_API_KEY")
                    }
                    #endif
                    model.attach(container.mainContext)
                    guard !model.needsOnboarding else { return }
                    await model.refresh()
                    model.startBackgroundDelivery()
                    // Only ever resumed, never requested here: asking for always-on
                    // location at launch is how that permission gets denied forever.
                    gym.resumeIfAuthorised(workoutsDuring: model.workoutLookup())
                }
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab = 0
    @State private var askingJett = false

    var body: some View {
        // QA: the home cards on their own, so a styling change can be looked at without
        // a seeded database and a walk through onboarding. Reached only by launch
        // argument, and the simulator's tap injection wedges often enough to need it.
        if Self.calendarHarness {
            NavigationStack { CalendarView() }
        } else if let signal = Self.detailHarness {
            NavigationStack { SignalDetailView(signal: signal) }
        } else if let signal = Self.insightsHarness {
            InsightsView(score: SampleScores.score(for: signal))
        } else if Self.cardGallery {
            CardGallery()
        // Onboarding is not a tab. It replaces the app until it is done, because a tab
        // bar offers four destinations to someone who has not said what they want yet.
        } else if model.needsOnboarding {
            OnboardingView()
        } else {
            main
        }
    }

    private static let cardGallery: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--card-gallery")
        #else
        false
        #endif
    }()

    /// `--calendar`, for the month grid. Pairs with `--demo-today`.
    private static let calendarHarness: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--calendar")
        #else
        false
        #endif
    }()

    /// `--signal sleep|recovery|strain`, for the detail screen behind a ring. Pairs with
    /// `--demo-today`, which supplies the physiology it reads.
    private static let detailHarness: Signal? = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--signal"),
              index + 1 < arguments.count else { return nil }
        return Signal(rawValue: arguments[index + 1])
        #else
        return nil
        #endif
    }()

    /// `--insights recovery|sleep|strain`, so the breakdown can be looked at in each
    /// state without six months of Health data behind it.
    private static let insightsHarness: SignalKind? = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--insights"),
              index + 1 < arguments.count else { return nil }
        return SignalKind(rawValue: arguments[index + 1])
        #else
        return nil
        #endif
    }()

    private var main: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView() }.hidingSystemTabBar().tag(0)
            NavigationStack { TrainView() }.hidingSystemTabBar().tag(1)
            NavigationStack { CalendarView() }.hidingSystemTabBar().tag(2)
            NavigationStack { ProfileView() }.hidingSystemTabBar().tag(3)
        }
        .task {
            if model.pendingCoachMessage != nil { askingJett = true }
        }
        .tint(Tokens.accent)
        // The bar floats, so it becomes part of the safe area rather than sitting on
        // top of the content — every screen scrolls clear of it without knowing it exists.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingTabBar(selection: $tab) { askingJett = true }
                .padding(.top, 6)
        }
        // fullScreenCover, not sheet: the large detent always leaves an inset strip of
        // the parent at the top, and iOS lays a dimming layer under a sheet — so the
        // material ends up blurring flat grey instead of the app.
        .fullScreenCover(isPresented: $askingJett) {
            CoachSheet()
                .presentationBackground(Tokens.messageCanvas)
        }
    }
}

private extension View {
    func hidingSystemTabBar() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}

/// Holds the chosen appearance and re-evaluates it when the clock crosses the boundary,
/// so a session left open overnight does not sit in yesterday's scheme.
@Observable
@MainActor
final class Appearance {
    private static let key = "appearance.preference.v1"

    var preference: AppearancePreference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: Self.key)
            refresh()
        }
    }

    private(set) var isDark: Bool
    private var timer: Task<Void, Never>?

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.key)
        let preference = stored.flatMap(AppearancePreference.init(rawValue:)) ?? .automatic
        self.preference = preference
        self.isDark = preference.wantsDark(at: Date())
        refresh()
    }

    /// Called on foreground too: an app backgrounded at dusk and opened at midnight has
    /// missed its own boundary.
    func refresh() {
        isDark = preference.wantsDark(at: Date())
        timer?.cancel()
        guard preference == .automatic,
              let next = Nightfall.nextChange(after: Date()) else { return }
        let seconds = next.timeIntervalSinceNow
        guard seconds > 0 else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}

/// The home cards with fixed numbers, for looking at.
private struct CardGallery: View {
    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 22) {
                    NutritionCard(calories: 1840, protein: 132, carbs: 190, fat: 58) {}
                    WeightTrendCard(latest: (date: Date(), kilograms: 74.2),
                                    series: [75.1, 74.9, 75.0, 74.6, 74.4, 74.5, 74.2],
                                    metric: true) {}
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.vertical, 24)
            }
        }
    }
}

#if DEBUG
/// Worked examples for the harness. Real arithmetic through the real engines, not
/// hand-written numbers — a gallery that fakes its own output cannot catch anything.
enum SampleScores {
    static func score(for kind: SignalKind) -> SignalScore {
        switch kind {
        case .recovery: return recovery
        case .sleep: return sleep
        case .strain: return strain
        }
    }

    /// A middling morning: HRV well down, resting heart rate up, everything else fine.
    private static var recovery: SignalScore {
        let readings = [
            MetricReading(kind: .hrv, value: 42, baseline: 58, zScore: -1.3, sampleCount: 60),
            MetricReading(kind: .restingHeartRate, value: 57, baseline: 52, zScore: 0.9, sampleCount: 60),
            MetricReading(kind: .sleepDebt, value: 1.2, baseline: 0.4, zScore: 0.5, sampleCount: 60),
            MetricReading(kind: .respiratoryRate, value: 14.6, baseline: 14.2, zScore: 0.2, sampleCount: 60),
            MetricReading(kind: .bloodOxygen, value: 97, baseline: 97.2, zScore: -0.2, sampleCount: 60),
        ]
        let history: [MetricKind: [Double]] = [
            .hrv: [58, 61, 55, 63, 57, 52, 49, 46, 42],
            .restingHeartRate: [52, 51, 53, 52, 54, 55, 56, 57, 57],
        ]
        return RecoveryScore.of(
            ReadinessEngine.evaluate(ReadinessInput(readings: readings, daysOfHistory: 90)),
            readings: readings, history: history)
    }

    /// A short, broken night after a hard day.
    private static var sleep: SignalScore {
        let calendar = Calendar.current
        func night(endingDaysAgo days: Int, hours: Double, deep: Double, rem: Double,
                   awake: Double) -> SleepBreakdown {
            let end = calendar.date(byAdding: .day, value: -days,
                                    to: calendar.startOfDay(for: Date()).addingTimeInterval(7 * 3600))!
            let start = end.addingTimeInterval(-(hours + awake) * 3600)
            var cursor = start
            func slice(_ length: Double, _ stage: SleepStage) -> SleepInterval {
                let interval = SleepInterval(start: cursor,
                                             end: cursor.addingTimeInterval(length * 3600),
                                             stage: stage)
                cursor = cursor.addingTimeInterval(length * 3600)
                return interval
            }
            let samples = [slice(hours * deep, .deep), slice(awake, .awake),
                           slice(hours * rem, .rem), slice(hours * (1 - deep - rem), .core)]
            return SleepAggregator.byWakeDay(samples)[calendar.startOfDay(for: end)]!
        }
        let tonight = night(endingDaysAgo: 0, hours: 6.1, deep: 0.08, rem: 0.13, awake: 0.7)
        let history = (1...14).map {
            night(endingDaysAgo: $0, hours: 7.6, deep: 0.16, rem: 0.22, awake: 0.3)
        }
        return SleepScore.of(SleepInput(
            breakdown: tonight, durationHours: 6.1, history: history,
            priorNights: [7.5, 6.8, 7.9, 6.2, 7.1, 6.6, 7.4],
            strain: 72, sleepingHeartRate: 56, daytimeHeartRate: 68))
    }

    /// An hour of intervals on top of an ordinary day on foot, plus a lifting session.
    private static var strain: SignalScore {
        var samples: [HeartRateSample] = []
        let midnight = Calendar.current.startOfDay(for: Date())
        func block(fromMinute: Int, count: Int, bpm: Double) {
            for step in 0..<count {
                samples.append(HeartRateSample(
                    start: midnight.addingTimeInterval(Double(fromMinute + step * 5) * 60),
                    minutes: 5, beatsPerMinute: bpm))
            }
        }
        block(fromMinute: 0, count: 84, bpm: 52)      // seven hours asleep
        block(fromMinute: 420, count: 120, bpm: 76)   // ten hours about the place
        block(fromMinute: 1020, count: 4, bpm: 128)   // twenty minutes warming up
        block(fromMinute: 1040, count: 6, bpm: 168)   // half an hour of intervals
        block(fromMinute: 1070, count: 3, bpm: 104)   // cooling down
        block(fromMinute: 1085, count: 60, bpm: 71)   // five hours of evening
        return StrainScore.of(StrainInput(
            samples: samples, restingHeartRate: 52, ageYears: 29, biologicalSex: .male,
            hardSets: 11))
    }
}
#endif
