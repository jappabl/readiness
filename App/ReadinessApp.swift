import SwiftUI
import SwiftData

@main
struct ReadinessApp: App {
    @State private var model = AppModel()
    @State private var store = Subscriptions()
    @State private var gym = GymPresence()

    private let container = Store.container

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(store)
                .environment(gym)
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
        // Onboarding is not a tab. It replaces the app until it is done, because a tab
        // bar offers four destinations to someone who has not said what they want yet.
        if model.needsOnboarding {
            OnboardingView()
        } else {
            main
        }
    }

    private var main: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView() }.hidingSystemTabBar().tag(0)
            NavigationStack { TrainView() }.hidingSystemTabBar().tag(1)
            NavigationStack { TrendsView() }.hidingSystemTabBar().tag(2)
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
