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
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    about
                    baselines
                    weights
                    coach
                    privacy
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.top, 4)
                .padding(.bottom, 96)
            }
        }
        .navigationTitle("Profile")
        .toolbarBackground(Tokens.canvas, for: .navigationBar)
        .onAppear { apiKey = Keychain.apiKey ?? "" }
    }

    private func heading(_ title: String) -> some View {
        Text(title).sectionHeading()
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("You")
            ListCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Goal").microLabel()
                    TextField("What are you training for?", text: Binding(
                        get: { profile.goal },
                        set: { profile.goal = $0; try? context.save() }), axis: .vertical)
                        .font(.system(size: 15)).lineLimit(1...3)
                }
                .padding(14)
                Divider().overlay(Tokens.hairline)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Limitations").microLabel()
                    TextField("Injuries the coach should respect", text: Binding(
                        get: { profile.limitations },
                        set: { profile.limitations = $0; try? context.save() }), axis: .vertical)
                        .font(.system(size: 15)).lineLimit(1...4)
                }
                .padding(14)
            }
        }
    }

    private var baselines: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Baselines")
            if let day = model.day {
                ListCard {
                    FieldRow(label: "History") { Text(Copy.count(day.daysOfHistory, "day")).monospacedDigit() }
                    Divider().overlay(Tokens.hairline).padding(.leading, 14)
                    FieldRow(label: "Confidence") {
                        Text(day.readiness.confidence.rawValue.capitalized)
                    }
                    ForEach(day.readings, id: \.kind) { reading in
                        Divider().overlay(Tokens.hairline).padding(.leading, 14)
                        FieldRow(label: reading.kind.displayName) {
                            Text(reading.baseline.formatted(.number.precision(.fractionLength(1)))
                                 + " " + reading.kind.unit).monospacedDigit()
                        }
                    }
                }
            } else {
                Text("Still reading your history.")
                    .font(.system(size: 15)).foregroundStyle(Tokens.textSecondary).bevelCard()
            }
        }
    }

    private var weights: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("How today is weighted")
            ListCard {
                ForEach(Array(MetricKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                    FieldRow(label: kind.displayName) {
                        Text((ReadinessEngine.weights[kind] ?? 0)
                            .formatted(.number.precision(.fractionLength(2)))).monospacedDigit()
                    }
                }
                Divider().overlay(Tokens.hairline).padding(.leading, 14)
                FieldRow(label: "Model") { Text(ReadinessEngine.modelVersion).monospacedDigit() }
            }
        }
    }

    private var coach: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Coach")
            ListCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Anthropic API key").microLabel()
                    SecureField("sk-ant-…", text: $apiKey)
                        .font(.system(size: 15))
                        .textContentType(.password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(14)
                Divider().overlay(Tokens.hairline)
                AccessoryRow(symbol: keySaved ? "checkmark.circle.fill" : "key",
                             label: keySaved ? "Saved to Keychain" : "Save key",
                             tint: apiKey.isEmpty ? Tokens.textSecondary : Tokens.accent) {
                    guard !apiKey.isEmpty else { return }
                    Keychain.setAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                    keySaved = true
                }
            }
        }
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Data")
            ListCard {
                FieldRow(label: "Apple Health") { Text("Read-only") }
            }
            footnote("Training guidance, not medical advice. Health data stays on this "
                     + "device and is never used for advertising.")
        }
    }
}
