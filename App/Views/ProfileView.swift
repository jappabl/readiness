import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    @State private var apiKey = ""
    @State private var keySaved = false

    private var profile: UserProfile {
        if let existing = profiles.first { return existing }
        let created = UserProfile()
        context.insert(created)
        try? context.save()
        return created
    }

    var body: some View {
        Form {
            Section("Goal") {
                TextField("What are you training for?", text: Binding(
                    get: { profile.goal }, set: { profile.goal = $0; try? context.save() }),
                    axis: .vertical)
                .lineLimit(1...3)
            }

            Section {
                TextField("Injuries or limitations the coach should respect", text: Binding(
                    get: { profile.limitations }, set: { profile.limitations = $0; try? context.save() }),
                    axis: .vertical)
                .lineLimit(1...4)
            } header: {
                Text("Limitations")
            } footer: {
                Text("The coach is told about these. It is not a clinician and will not "
                     + "treat or diagnose anything.")
            }

            Section("Baselines") {
                if let day = model.day {
                    LabeledContent("History", value: "\(day.daysOfHistory) days")
                    LabeledContent("Confidence", value: day.readiness.confidence.rawValue.capitalized)
                    ForEach(day.readings, id: \.kind) { reading in
                        LabeledContent(reading.kind.displayName,
                                       value: reading.baseline.formatted(.number.precision(.fractionLength(1)))
                                       + " " + reading.kind.unit)
                    }
                } else {
                    Text("Still reading your history.").foregroundStyle(Tokens.textSecondary)
                }
            }

            Section {
                ForEach(MetricKind.allCases, id: \.self) { kind in
                    LabeledContent(kind.displayName,
                                   value: (ReadinessEngine.weights[kind] ?? 0)
                                        .formatted(.number.precision(.fractionLength(2))))
                }
                LabeledContent("Model", value: ReadinessEngine.modelVersion)
            } header: {
                Text("How today's call is weighted")
            } footer: {
                Text("Every weight is visible because none of them is proven. They come from "
                     + "published effect sizes, not from your data — yet.")
            }

            Section {
                SecureField("Anthropic API key", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Button("Save key") {
                    Keychain.setAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                    keySaved = true
                }
                .tint(Tokens.accent)
                .disabled(apiKey.isEmpty)
                if keySaved {
                    Label("Saved to the Keychain", systemImage: "checkmark.circle")
                        .font(.footnote).foregroundStyle(Tokens.textSecondary)
                }
            } header: {
                Text("Coach")
            } footer: {
                Text("The coach needs your own Anthropic API key. It is stored in the "
                     + "device Keychain. Only derived summaries are sent — never your raw "
                     + "health records.")
            }

            Section {
                Text("Apple Health, read-only")
                Text("Your health data never leaves this device and is never used for advertising.")
                    .font(.footnote).foregroundStyle(Tokens.textSecondary)
            } header: {
                Text("Data sources")
            }

            Section {
                Text("This app gives training guidance. It is not medical advice, it does not "
                     + "diagnose, and it cannot see anything your watch does not measure. "
                     + "If something feels wrong, talk to a clinician rather than this app.")
                    .font(.footnote).foregroundStyle(Tokens.textSecondary)
            }
        }
        .navigationTitle("Profile")
        .onAppear { apiKey = Keychain.apiKey ?? "" }
    }
}
