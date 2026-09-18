import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(Subscriptions.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    @State private var apiKey = ""
    @State private var keySaved = false
    @State private var showingPaywall = false

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
                    subscription
                    baselines
                    weights
                    coach
                    privacy
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
        }
        .navigationTitle("Profile")
        .toolbarBackground(Tokens.canvas, for: .navigationBar)
        .onAppear { apiKey = Keychain.apiKey ?? "" }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView { showingPaywall = false }
        }
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
                // Not free text: this field decides what the home screen is made of,
                // so it has to stay one of the goals the composition knows about.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goal").microLabel()
                    Menu {
                        Picker("Goal", selection: Binding(
                            get: { model.goal ?? .getStronger },
                            set: { model.setGoal($0, in: context) })) {
                            ForEach(TrainingGoal.allCases, id: \.self) { goal in
                                Label(goal.title, systemImage: goal.symbol).tag(goal)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text((model.goal ?? .getStronger).title)
                                .font(.system(size: 15))
                                .foregroundStyle(Tokens.textPrimary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Tokens.textSecondary)
                        }
                    }
                    Text((model.goal ?? .getStronger).promise)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
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

    private var subscription: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Coach Jett")
            ListCard {
                if store.isSubscribed {
                    FieldRow(label: "Plan") {
                        Text("Pro").foregroundStyle(Tokens.accent)
                    }
                    Divider().overlay(Tokens.hairline).padding(.leading, 14)
                    AccessoryRow(symbol: "gear", label: "Manage subscription") {
                        // Apple owns cancellation and billing; sending people anywhere
                        // else for it is both against the rules and worse.
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            openURL(url)
                        }
                    }
                } else {
                    let allowance = Paywall.allowance(used: model.coachMessagesUsed,
                                                      isSubscribed: false)
                    FieldRow(label: "Free answers left") {
                        Text("\(allowance.remaining ?? 0) of \(Paywall.freeMessages)")
                            .monospacedDigit()
                    }
                    Divider().overlay(Tokens.hairline).padding(.leading, 14)
                    AccessoryRow(symbol: "sparkle", label: "See plans", tint: Tokens.accent) {
                        showingPaywall = true
                    }
                }
            }
            footnote(store.isSubscribed
                     ? "Unlimited answers. There is a burst limit to stop runaway usage, "
                       + "which a conversation never reaches."
                     : "Everything Readiness measures is free. Jett is the part with a "
                       + "cost every time you ask.")
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
