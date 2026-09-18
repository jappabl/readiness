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

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                NavigationStack { TodayView() }
                    .tabItem { Label("Today", systemImage: "sun.max") }.tag(0)
                NavigationStack { TrainView() }
                    .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }.tag(1)
                NavigationStack { TrendsView() }
                    .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }.tag(2)
                NavigationStack { ProfileView() }
                    .tabItem { Label("Profile", systemImage: "person") }.tag(3)
            }
            .tint(Tokens.accent)

            // The coach lives over Today rather than beside it, so it can blur the
            // app behind it — including the tab bar.
            if tab == 0 { CoachLayer() }
        }
    }
}
