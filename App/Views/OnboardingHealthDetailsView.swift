import SwiftUI

/// A single conversational attachment, with one deliberate choice in focus.
/// Selector positions are previews; only the labelled confirmation saves a value.
struct OnboardingHealthDetailsView: View {
    let fields: [HealthProfile.Field]
    let onSave: (HealthProfile) -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var draft = HealthProfile()
    @State private var metricHeight: Bool
    @State private var rulerValue: Int?
    @State private var birthday: Date

    init(fields: [HealthProfile.Field], metric: Bool,
         onSave: @escaping (HealthProfile) -> Void, onSkip: @escaping () -> Void) {
        self.fields = fields; self.onSave = onSave; self.onSkip = onSkip
        _metricHeight = State(initialValue: metric)
        _rulerValue = State(initialValue: metric ? 170 : 67)
        // The first of January, not today's date twenty-five years ago. Subtracting
        // years from now leaves the month and day where they are, so the wheel opened on
        // somebody's birthday being the day they installed the app: two testers noticed,
        // and one of them left it, so his profile now says an age he never gave. A
        // placeholder should look like one.
        let january = DateComponents(year: Calendar.current.component(.year, from: Date()) - 25,
                                     month: 1, day: 1)
        _birthday = State(initialValue: Calendar.current.date(from: january) ?? Date())
    }

    private var current: HealthProfile.Field { fields[index] }
    private var heightCM: Double {
        metricHeight ? Double(rulerValue ?? 170) : Double(rulerValue ?? 67) * 2.54
    }
    private var heightLabel: String {
        let value = rulerValue ?? (metricHeight ? 170 : 67)
        return metricHeight ? "\(value) cm" : "\(value / 12) ft \(value % 12) in"
    }
    /// Only where the screen cannot say it itself. Asking somebody their sex without
    /// saying why is the one of these three that earns a word.
    private var explanation: String? {
        switch current {
        case .biologicalSex:
            return "Only used when it matters for your coaching, like protein and "
                 + "calorie targets. Jett is never told it otherwise."
        case .dateOfBirth:
            return "Your birthday stays on this device. Jett only ever gets your age."
        case .height: return nil
        }
    }

    private var title: String {
        switch current {
        case .height: return "Your height"
        case .dateOfBirth: return "Your birthday"
        case .biologicalSex: return "Biological sex"
        }
    }

    var body: some View {
        VStack(spacing: 18) {
            // A single field is somebody correcting one measure from Profile, not a
            // run through onboarding. "1 of 1" says nothing, and there is nothing to
            // skip when the sheet already swipes away.
            if fields.count > 1 {
                HStack {
                    Text("OPTIONAL · \(index + 1) OF \(fields.count)")
                        .font(.caption2.weight(.medium)).foregroundStyle(Tokens.textSecondary)
                    Spacer(minLength: 12)
                    Button(index == 0 && draft == HealthProfile() ? "Skip all" : "Skip rest") { finish() }
                        .font(.subheadline).frame(minHeight: 44)
                }
            }
            HStack {
                if index > 0 {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { index -= 1 }
                    } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Previous detail")
                }
                Text(title).font(.title3.weight(.semibold))
                if let note = explanation { InfoDot(text: note) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                switch current {
                case .height: heightSelector
                case .dateOfBirth: birthdaySelector
                case .biologicalSex: sexSelector
                }
            }
            .id(index)
            .transition(.opacity)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        // A card, but only where it is one thing among many. In onboarding this is an
        // attachment sitting in a conversation and needs an edge to be a thing at all.
        // Presented on its own it is the whole sheet, and a rounded card inside a
        // rounded sheet is two edges saying the same thing with a stripe of dead space
        // between them.
        .background {
            if fields.count > 1 {
                RoundedRectangle(cornerRadius: 24).fill(Tokens.surface)
                    .overlay(RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(Tokens.hairline, lineWidth: 1))
            }
        }
        .tint(Tokens.messageOutgoing)
    }

    private var heightSelector: some View {
        VStack(spacing: 16) {
            Picker("Height units", selection: $metricHeight) {
                Text("cm").tag(true)
                Text("ft + in").tag(false)
            }
            .pickerStyle(.segmented).frame(maxWidth: 180).ticksOnChange(metricHeight)
            .onChange(of: metricHeight) { old, new in
                let value = Double(rulerValue ?? (old ? 170 : 67))
                rulerValue = Int((new ? value * 2.54 : value / 2.54).rounded())
            }
            Text(heightLabel)
                .font(.largeTitle.weight(.semibold)).monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Tokens.textPrimary)
            HeightRuler(value: $rulerValue, metric: metricHeight)
            confirmButton("Use \(heightLabel)") {
                draft.heightCM = (heightCM * 100).rounded() / 100
                advance()
            }
            skipButton("Skip height") { draft.heightCM = nil; advance() }
        }
    }

    private var birthdaySelector: some View {
        VStack(spacing: 12) {
            DatePicker("Date of birth", selection: $birthday,
                       in: Calendar(identifier: .gregorian).date(byAdding: .year, value: -120, to: Date())!...Date(),
                       displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden().ticksOnChange(birthday)
                .environment(\.calendar, Calendar(identifier: .gregorian))
            confirmButton("Use \(birthday.formatted(date: .abbreviated, time: .omitted))") {
                draft.dateOfBirth = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: birthday)
                advance()
            }
            skipButton("Skip birthday") { draft.dateOfBirth = nil; advance() }
        }
    }

    private var sexSelector: some View {
        VStack(spacing: 10) {
            ForEach(HealthProfile.BiologicalSex.allCases, id: \.self) { value in
                Button {
                    draft.biologicalSex = value
                    advance()
                } label: {
                    HStack {
                        Text(value.title).font(.body.weight(.medium))
                        Spacer()
                        Image(systemName: "arrow.right").font(.subheadline)
                    }
                    .padding(.horizontal, 18).frame(minHeight: 56)
                    .foregroundStyle(Tokens.textPrimary)
                    .background(Tokens.messageIncoming, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(PressableStyle())
            }
            skipButton("Prefer not to share") { draft.biologicalSex = nil; advance() }
        }
    }

    private func confirmButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(Tokens.messageOnOutgoing)
                .background(Tokens.messageOutgoing, in: Capsule())
        }
        .buttonStyle(PressableStyle())
    }
    /// Skipping is a step in a flow. Correcting one measure from Profile is not a flow,
    /// and there the sheet already swipes away, so a second word for "leave it" is two
    /// ways out of a screen with one thing on it.
    @ViewBuilder
    private func skipButton(_ label: String, action: @escaping () -> Void) -> some View {
        if fields.count > 1 {
            Button(label, action: action).font(.subheadline)
                .foregroundStyle(Tokens.textSecondary).frame(minHeight: 44)
        }
    }
    private func advance() {
        Haptics.decided()
        if index + 1 < fields.count {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { index += 1 }
        } else { finish() }
    }
    private func finish() {
        if draft == HealthProfile() { onSkip() }
        else { onSave(draft) }
    }
}

private struct HeightRuler: View {
    @Binding var value: Int?
    let metric: Bool
    private var values: ClosedRange<Int> { metric ? 40...250 : 16...98 }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(values, id: \.self) { tick in
                            VStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(Tokens.textSecondary.opacity(tick % (metric ? 5 : 12) == 0 ? 0.65 : 0.3))
                                    .frame(width: 1.5, height: tick % (metric ? 5 : 12) == 0 ? 32 : 18)
                                    .frame(height: 32, alignment: .top)
                                if tick % (metric ? 5 : 12) == 0 {
                                    Text(metric ? "\(tick)" : "\(tick / 12)′")
                                        .font(.caption2).foregroundStyle(Tokens.textSecondary)
                                        .fixedSize()
                                }
                            }
                            .frame(width: 10).id(tick)
                            .onTapGesture { value = tick }
                        }
                    }
                    .scrollTargetLayout()
                }
                .safeAreaPadding(.horizontal, max(0, (geometry.size.width - 10) / 2))
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $value, anchor: .center)
                // A tick per notch under the thumb. This is the one control in the app
                // that is literally a dial, and a silent dial feels broken.
                .ticksOnChange(value)
                .onAppear { proxy.scrollTo(value ?? (metric ? 170 : 67), anchor: .center) }
                .overlay(alignment: .top) {
                    Capsule().fill(Tokens.messageOutgoing).frame(width: 3, height: 42)
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(height: 82)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Height ruler")
        .accessibilityValue(metric ? "\(value ?? 170) centimeters" : "\((value ?? 67) / 12) feet \((value ?? 67) % 12) inches")
        .accessibilityAdjustableAction { direction in
            let current = value ?? (metric ? 170 : 67)
            switch direction {
            case .increment: value = min(values.upperBound, current + 1)
            case .decrement: value = max(values.lowerBound, current - 1)
            @unknown default: break
            }
        }
    }
}
