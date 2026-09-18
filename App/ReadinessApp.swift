import SwiftUI
import SwiftData

@main
struct ReadinessApp: App {
    @State private var model = AppModel()

    private let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: LiftConfig.self, DailyMetricRow.self,
                     ReadinessRow.self, PrescriptionRow.self, OutcomeRow.self)
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
            NavigationStack { HomeView() }
                .tabItem { Label("Today", systemImage: "figure.strengthtraining.traditional") }
            NavigationStack { HistoryView() }
                .tabItem { Label("History", systemImage: "list.bullet") }
        }
        .tint(Tokens.accent)
    }
}
