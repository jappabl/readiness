import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @Environment(Subscriptions.self) private var store
    @Environment(GymPresence.self) private var gym
    @Environment(Appearance.self) private var appearance
    @Environment(\.openURL) private var openURL
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @State private var editing: HealthProfile.Field?
    @State private var loggingWeight = false
    @State private var editorHeight: CGFloat = 320
    @Environment(Notifications.self) private var notifications

    private var metric: Bool { profiles.first?.unitsAreMetric ?? model.onboarding.unitsAreMetric }

    @State private var showingPaywall = false
    @State private var showingSharing = false
    @State private var attestationResult: String?
    @State private var checkingAttestation = false

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
                    memory
                    subscription
                    baselines
                    weights
                    look
                    speaking
                    atTheGym
                    privacy
                    #if DEBUG
                    attestation
                    #endif
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.top, 4)
                .clearsTabBar()
            }
        }
        .navigationTitle("Profile")
        .toolbarBackground(Tokens.canvas, for: .navigationBar)
        .sheet(isPresented: $showingSharing) {
            CoachSharingSheet(onAllow: {
                model.coachSharingAllowed = true
                showingSharing = false
            }, onCancel: { showingSharing = false })
        }
        .fullScreenCover(isPresented: $showingPaywall) {
            PaywallView { showingPaywall = false }
        }
        .sheet(item: $editing) { field in
            // No chrome. One control, and swiping the sheet down is the way out.
            Group {
                OnboardingHealthDetailsView(
                    fields: [field], metric: metric,
                    onSave: { details in
                        model.updateHealthDetails(details, in: context)
                        editing = nil
                    },
                    onSkip: { editing = nil })
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.top, 10)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, alignment: .top)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.onChange(of: proxy.size.height, initial: true) {
                                _, height in editorHeight = height
                            }
                        }
                    }
            }
            // As tall as what is in it. A wheel, a ruler and three buttons are three
            // different heights, and a detent picked for one leaves the other two
            // sitting in a half-empty sheet.
            .presentationDetents([.height(editorHeight)])
            .presentationDragIndicator(.visible)
            .presentationBackground(Tokens.surface)
        }
        .sheet(isPresented: $loggingWeight) { WeightLogView { _ in loggingWeight = false } }
    }

    private func heading(_ title: String, info: String? = nil) -> some View {
        SectionHeadingRow(title: title, info: info)
    }

    private func footnote(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 2)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("You")
            ListCard {
                personal
                Divider().overlay(Tokens.hairline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Goals").microLabel()
                    ForEach(TrainingGoal.allCases, id: \.self) { goal in
                        let selected = model.goals.contains(goal)
                        Button {
                            Haptics.selected()
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

    /// One card, not a section of rows. Everything else in Profile is something they
    /// told the app; this is the only thing the app wrote about them, and it earns being
    /// its own object rather than a line between goals and billing.
    /// Height, age, sex and weight, in the section called You.
    ///
    /// They were collected in onboarding, read from Health where it has them, and then
    /// only ever visible to Jett. Somebody looking at a section about themselves expects
    /// to find them there, and a value that cannot be checked is a value that quietly
    /// stays wrong: a height typed in the wrong unit shapes every answer afterwards.
    ///
    /// Read from Health where Health has it, so what is shown is what the coaching
    /// actually used, not a second copy that drifted.
    @ViewBuilder
    private var personal: some View {
        let profile = model.effectiveHealthProfile
        VStack(alignment: .leading, spacing: 0) {
            FieldRow(label: "Height") {
                measure(heightText(profile.heightCM)) { editing = .height }
            }
            Divider().overlay(Tokens.hairline).padding(.leading, 14)
            FieldRow(label: "Age") {
                measure(profile.ageYears().map { "\($0)" }) { editing = .dateOfBirth }
            }
            Divider().overlay(Tokens.hairline).padding(.leading, 14)
            FieldRow(label: "Sex") {
                measure(profile.biologicalSex?.title) { editing = .biologicalSex }
            }
            Divider().overlay(Tokens.hairline).padding(.leading, 14)
            // Weight is the one that moves, so it is a log rather than a setting. The
            // row states the latest and hands over to the place that records them.
            FieldRow(label: "Weight") {
                Button { loggingWeight = true } label: {
                    HStack(spacing: 6) {
                        Text(weightText ?? "Add")
                            .foregroundStyle(weightText == nil ? Tokens.accent : Tokens.textPrimary)
                            .monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.footnote).foregroundStyle(Tokens.textSecondary)
                    }
                    .frame(minHeight: 34).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A value, or an invitation to supply it. Never a dash: a blank reads as broken,
    /// where "Add" reads as something the person can do something about.
    private func measure(_ value: String?, edit: @escaping () -> Void) -> some View {
        Button(action: edit) {
            HStack(spacing: 6) {
                Text(value ?? "Add")
                    .foregroundStyle(value == nil ? Tokens.accent : Tokens.textPrimary)
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.footnote).foregroundStyle(Tokens.textSecondary)
            }
            .frame(minHeight: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func heightText(_ centimetres: Double?) -> String? {
        guard let centimetres else { return nil }
        if metric { return "\(Int(centimetres.rounded())) cm" }
        let inches = centimetres / 2.54
        return "\(Int(inches) / 12) ft \(Int(inches.rounded()) % 12) in"
    }

    private var weightText: String? {
        guard let latest = model.latestWeight else { return nil }
        let shown = metric ? latest.kilograms : latest.kilograms * 2.2046226218
        return "\(shown.formatted(.number.precision(.fractionLength(0...1)))) \(metric ? "kg" : "lb")"
    }

    private var memory: some View {
        NavigationLink { MemoryView() } label: {
            MemoryCard(notes: model.coachMemory.notes)
        }
        .buttonStyle(PressableStyle())
    }

    private var subscription: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Coach Jett", info: store.isSubscribed
                    ? "Unlimited answers. There is a burst limit to stop runaway usage, "
                      + "which a conversation never reaches."
                    : "Everything the app measures is free. Jett is the part with a "
                      + "cost every time you ask.")
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

    /// Jett starting the conversation, rather than answering one.
    ///
    /// Off until asked for, and asked for here rather than on first launch: a permission
    /// sheet before anybody knows what the app does is a permission sheet people decline.
    private var speaking: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("When Jett speaks first", info:
                "A verdict on the morning after a night worth mentioning, a warning if "
                + "your temperature is up, a target on a night that needs more sleep "
                + "than usual, and a pattern when one appears. Never for the sake of it.")
            ListCard {
                Button {
                    Haptics.decided()
                    if notifications.isEnabled { notifications.disable() }
                    else { Task { await notifications.enable() } }
                } label: {
                    HStack {
                        Text("Let Jett reach me")
                            .font(.system(size: 15))
                            .foregroundStyle(Tokens.textPrimary)
                        Spacer(minLength: 12)
                        Toggle("", isOn: .constant(notifications.isEnabled))
                            .labelsHidden().tint(Tokens.accent).allowsHitTesting(false)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if notifications.systemStatus == .denied {
                    Divider().overlay(Tokens.hairline)
                    AccessoryRow(symbol: "gear", label: "Turn on in Settings",
                                 tint: Tokens.textSecondary) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }
            }
        }
    }

    /// Off until asked for. The permission this needs is the one people are most
    /// suspicious of, so the reason sits directly above the switch rather than in a
    /// dialog they have already dismissed.
    private var atTheGym: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("At the gym", info: gymFootnote)
            ListCard {
                // The whole row is the control. A bare Toggle only responds on the
                // switch itself outside a List, which is a 50pt target on the far edge.
                Button {
                    Haptics.decided()
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

    /// Light by default because a coach should not look like a terminal, dark at night
    /// because this gets opened in a dark bedroom. Anyone who disagrees says so once.
    private var look: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("Look")
            ListCard {
                ForEach(Array(AppearancePreference.allCases.enumerated()), id: \.element) { index, option in
                    if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                    Button {
                        Haptics.decided()
                        appearance.preference = option
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.system(size: 15))
                                    .foregroundStyle(Tokens.textPrimary)
                                if let detail = option.detail {
                                    Text(detail)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Tokens.textSecondary)
                                }
                            }
                            Spacer(minLength: 8)
                            if appearance.preference == option {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Tokens.accent)
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Whether this install can prove itself to the proxy.
    ///
    /// Debug only, and it exists for one afternoon: attestation has to be confirmed
    /// working on real hardware before the server is told to accept nothing else.
    /// Flipping that flag blind means the failure mode is an app that cannot reach its
    /// own backend, on every phone at once.
    #if DEBUG
    private var attestation: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("App Attest")
            ListCard {
                FieldRow(label: "This install") { Text(AppAttest.status) }
                Divider().overlay(Tokens.hairline)
                Button(checkingAttestation ? "Checking..." : "Check attestation") {
                    Haptics.light()
                    checkingAttestation = true
                    Task {
                        attestationResult = await Backend.attestationCheck()
                        checkingAttestation = false
                    }
                }
                .disabled(checkingAttestation)
                .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                if let attestationResult {
                    Divider().overlay(Tokens.hairline)
                    Text(attestationResult)
                        .font(.footnote).foregroundStyle(Tokens.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                }
            }
        }
    }
    #endif

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
