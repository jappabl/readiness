import SwiftUI
import SwiftData

/// The entire onboarding: name your main lifts and what you are currently working with.
/// Nothing else is collected, because nothing else changes the weight on the bar.
struct OnboardingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model

    @State private var drafts: [Draft] = Draft.starters

    struct Draft: Identifiable {
        let id = UUID()
        var name: String
        var weight: Double
        var increment: Double
        var include: Bool

        static let starters: [Draft] = [
            Draft(name: "Back squat", weight: 225, increment: 10, include: true),
            Draft(name: "Bench press", weight: 165, increment: 5, include: true),
            Draft(name: "Deadlift", weight: 275, increment: 10, include: true),
            Draft(name: "Overhead press", weight: 115, increment: 5, include: false),
        ]
    }

    var body: some View {
        Form {
            Section {
                Text("Name your main lifts and what you're currently working with. "
                     + "Everything else is read from Health.")
                    .font(.subheadline)
                    .foregroundStyle(Tokens.textSecondary)
            }

            ForEach($drafts) { $draft in
                Section {
                    Toggle(isOn: $draft.include) {
                        TextField("Lift", text: $draft.name)
                    }
                    .tint(Tokens.accent)

                    if draft.include {
                        LabeledContent("Working weight") {
                            TextField("Weight", value: $draft.weight,
                                      format: .number.precision(.fractionLength(0)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                        }
                        Picker("Smallest jump", selection: $draft.increment) {
                            Text("2.5 lb").tag(2.5)
                            Text("5 lb").tag(5.0)
                            Text("10 lb").tag(10.0)
                        }
                    }
                }
            }

            Section {
                Button("Start") { save() }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(!drafts.contains { $0.include })
            } footer: {
                Text("Training guidance, not medical advice. Your health data stays on this device.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Tokens.canvas)
    }

    private func save() {
        for (index, draft) in drafts.enumerated() where draft.include {
            context.insert(LiftConfig(name: draft.name, workingWeight: draft.weight,
                                      increment: draft.increment, order: index))
        }
        try? context.save()
        Task { await model.refresh() }
    }
}
