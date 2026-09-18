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
    var body: some View {
        TabView {
            NavigationStack { TodayView() }
                .tabItem { Label("Today", systemImage: "sun.max") }
            NavigationStack { TrainView() }
                .tabItem { Label("Train", systemImage: "figure.strengthtraining.traditional") }
            NavigationStack { CoachView() }
                .tabItem { Label("Coach", systemImage: "bubble.left.and.text.bubble.right") }
            NavigationStack { TrendsView() }
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
            NavigationStack { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person") }
        }
        .tint(Tokens.accent)
    }
}
