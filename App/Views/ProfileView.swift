import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(Subscriptions.self) private var store
    @Environment(GymPresence.self) private var gym
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    @State private var apiKey = ""
    @State private var keySaved = false
    @State private var showingPaywall = false
    @State private var showingSharing = false

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
                    atTheGym
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
        .sheet(isPresented: $showingSharing) {
            CoachSharingSheet(onAllow: {
                model.coachSharingAllowed = true
                showingSharing = false
            }, onCancel: { showingSharing = false })
        }
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goals").microLabel()
                    ForEach(TrainingGoal.allCases, id: \.self) { goal in
                        let selected = model.goals.contains(goal)
                        Button {
                            var goals = model.goals
                            if selected { goals.remove(goal) } else { goals.insert(goal) }
                            model.setGoals(goals, in: context)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected ? Tokens.messageOutgoing : Tokens.textSecondary)
                                Text(goal.title).foregroundStyle(Tokens.textPrimary)
                                Spacer(minLength: 0)
                            }
                            .font(.body).frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(selected && model.goals.count == 1)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityHint(selected && model.goals.count == 1 ? "Keep at least one goal" : "")
                    }
                    Text("Pick one or more. Your home screen and coaching reflect all your goals.")
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
                     : "Everything the app measures is free. Jett is the part with a "
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

    /// Off until asked for. The permission this needs is the one people are most
    /// suspicious of, so the reason sits directly above the switch rather than in a
    /// dialog they have already dismissed.
    private var atTheGym: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("At the gym")
            ListCard {
                // The whole row is the control. A bare Toggle only responds on the
                // switch itself outside a List, which is a 50pt target on the far edge.
                Button {
                    if gym.wantsWatching { gym.stopWatching() }
                    else { gym.requestPermission(workoutsDuring: model.workoutLookup()) }
                } label: {
                    HStack {
                        Text("Notice when I'm training")
                            .font(.system(size: 15))
                            .foregroundStyle(Tokens.textPrimary)
                        Spacer(minLength: 12)
                        Toggle("", isOn: .constant(gym.wantsWatching))
                            .labelsHidden()
                            .tint(Tokens.accent)
                            .allowsHitTesting(false)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !gym.knownGyms.isEmpty {
                    Divider().background(Tokens.hairline)
                    FieldRow(label: gym.knownGyms.count == 1 ? "Your gym" : "Your gyms") {
                        Button("Forget") { gym.forgetGyms() }
                            .font(.system(size: 14))
                    }
                }
            }
            footnote(gymFootnote)
        }
    }

    private var gymFootnote: String {
        if gym.needsSettings {
            return "iOS is holding location back. Settings, Coach Jett, Location, "
                 + "Always "
                 + "turns this on."
        }
        if gym.knownGyms.isEmpty {
            return "Jett offers to log sets when you've been at your gym a few minutes. "
                 + "Nothing about where you go leaves this device."
        }
        return "Learned: " + gym.knownGyms.map(\.name).joined(separator: ", ")
             + ". Nothing about where you go leaves this device."
    }

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Data")
            ListCard {
                FieldRow(label: "Apple Health") { Text("Read + optional logs") }
                Divider().overlay(Tokens.hairline)
                Button("Connect or refresh Health") { Task { await model.refresh(requestHealthAccess: true); model.startBackgroundDelivery() } }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                Divider().overlay(Tokens.hairline)
                Toggle("Share summaries for AI coaching", isOn: Binding(
                    get: { model.coachSharingAllowed },
                    set: { allowed in
                        if allowed { showingSharing = true }
                        else { model.coachSharingAllowed = false }
                    }))
                    .font(.subheadline).padding(14)
            }
            footnote("Manage read and write permissions in the Health app.")
            footnote("Health is read on your device. If you allow AI coaching, your messages, "
                     + "profile, check-ins, training plan, and derived health summaries go to Coach Jett's "
                     + "server and the AI provider it uses to write the reply. "
                     + "Your birthday and raw Health records stay here. Turning sharing off stops future requests; "
                     + "it cannot recall data already sent. Health data is not used for advertising.")
            footnote("Sleep uses duration and recorded continuity, plus regularity when enough history exists. Duration alone is not a sleep score. "
                     + "Heart metrics cannot tell us how stressed you feel. Training guidance, not medical advice.")
            footnote("Meal photos and portion notes go to the same places, and only when you approve "
                     + "an estimate. No Health history is sent for meal estimates.")
        }
    }
}
