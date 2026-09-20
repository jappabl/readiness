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
        _birthday = State(initialValue: Calendar.current.date(byAdding: .year, value: -25, to: Date())!)
    }

    private var current: HealthProfile.Field { fields[index] }
    private var heightCM: Double {
        metricHeight ? Double(rulerValue ?? 170) : Double(rulerValue ?? 67) * 2.54
    }
    private var heightLabel: String {
        let value = rulerValue ?? (metricHeight ? 170 : 67)
        return metricHeight ? "\(value) cm" : "\(value / 12) ft \(value % 12) in"
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
            HStack {
                Text("OPTIONAL · \(index + 1) OF \(fields.count)")
                    .font(.caption2.weight(.medium)).foregroundStyle(Tokens.textSecondary)
                Spacer(minLength: 12)
                Button(index == 0 && draft == HealthProfile() ? "Skip all" : "Skip rest") { finish() }
                    .font(.subheadline).frame(minHeight: 44)
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
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Tokens.hairline, lineWidth: 1))
        .tint(Tokens.messageOutgoing)
    }

    private var heightSelector: some View {
        VStack(spacing: 16) {
            Picker("Height units", selection: $metricHeight) {
                Text("cm").tag(true)
                Text("ft + in").tag(false)
            }
            .pickerStyle(.segmented).frame(maxWidth: 180)
            .onChange(of: metricHeight) { old, new in
                let value = Double(rulerValue ?? (old ? 170 : 67))
                rulerValue = Int((new ? value * 2.54 : value / 2.54).rounded())
            }
            Text(heightLabel)
                .font(.largeTitle.weight(.semibold)).monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(Tokens.textPrimary)
            HeightRuler(value: $rulerValue, metric: metricHeight)
            Text("Slide to your height")
                .font(.caption).foregroundStyle(Tokens.textSecondary)
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
                .datePickerStyle(.wheel).labelsHidden()
                .environment(\.calendar, Calendar(identifier: .gregorian))
            Text("Your birthday stays here. Jett only gets your age.")
                .font(.caption).foregroundStyle(Tokens.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            confirmButton("Use \(birthday.formatted(date: .abbreviated, time: .omitted))") {
                draft.dateOfBirth = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: birthday)
                advance()
            }
            skipButton("Skip birthday") { draft.dateOfBirth = nil; advance() }
        }
    }

    private var sexSelector: some View {
        VStack(spacing: 10) {
            Text("Only used when it matters for your coaching.")
                .font(.subheadline).foregroundStyle(Tokens.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
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
    private func skipButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action).font(.subheadline)
            .foregroundStyle(Tokens.textSecondary).frame(minHeight: 44)
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
