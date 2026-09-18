import SwiftUI
import SwiftData

@main
struct ReadinessApp: App {
    @State private var model = AppModel()

    private let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: WorkoutTemplate.self, TemplateExercise.self,
                     WorkoutSession.self, LoggedSet.self,
                     CheckInRow.self, DailyMetricRow.self,
                     RecommendationRow.self, UserProfile.self)
        } catch {
            fatalError("Could not create the local store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task {
                    model.attach(container.mainContext)
                    await model.refresh()
                    model.startBackgroundDelivery()
                }
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @State private var tab = 0
    @State private var askingJett = false

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView() }.hidingSystemTabBar().tag(0)
            NavigationStack { TrainView() }.hidingSystemTabBar().tag(1)
            NavigationStack { TrendsView() }.hidingSystemTabBar().tag(2)
            NavigationStack { ProfileView() }.hidingSystemTabBar().tag(3)
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
                .presentationBackground(.ultraThinMaterial)
        }
    }
}

private extension View {
    func hidingSystemTabBar() -> some View {
        toolbar(.hidden, for: .tabBar)
    }
}
