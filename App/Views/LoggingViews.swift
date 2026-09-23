import SwiftUI
import PhotosUI
import AVFoundation

struct WeightLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var whole = 150
    @State private var decimal = 0
    @State private var metric = false
    @State private var health = true
    @State private var busy = false
    @State private var error: String?
    let onSaved: (String) -> Void
    private var kilograms: Double { BodyMass.kilograms(display: Double(whole) + Double(decimal) / 10, metric: metric) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Text("Where are you today?").font(.title2.weight(.semibold)).padding(.top, 24)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Double(whole) + Double(decimal) / 10, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text(metric ? "kg" : "lb").font(.title3).foregroundStyle(.secondary)
                }.accessibilityLabel("Weight \(whole) point \(decimal) \(metric ? "kilograms" : "pounds")")
                HStack(spacing: 0) {
                    Picker("Weight", selection: $whole) {
                        ForEach(metric ? 15...500 : 34...1102, id: \.self) { Text("\($0)").tag($0) }
                    }.pickerStyle(.wheel)
                    Text(".").font(.title.bold())
                    Picker("Tenths", selection: $decimal) {
                        ForEach(0...9, id: \.self) { Text("\($0)").tag($0) }
                    }.pickerStyle(.wheel).frame(width: 85)
                }.frame(height: 160).clipped()
                Picker("Units", selection: Binding(get: { metric }, set: { new in
                    let kg = kilograms
                    metric = new
                    set(BodyMass.display(kilograms: kg, metric: new))
                })) {
                    Text("Pounds").tag(false); Text("Kilos").tag(true)
                }.pickerStyle(.segmented).ticksOnChange(metric)
                Toggle("Save to Apple Health", isOn: $health)
                Text("Adds a new weight measurement. Your earlier readings stay intact.")
                    .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Button { Haptics.committed(); save() } label: {
                    HStack { Spacer(); if busy { ProgressView().tint(.white) } else { Text("Save weight") }; Spacer() }.padding(.vertical, 9)
                }.buttonStyle(.borderedProminent).disabled(busy || !BodyMass.isValid(kilograms: kilograms))
                Spacer(minLength: 0)
            }.padding(.horizontal, 24)
                .navigationTitle("Log weight").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
                .onAppear { metric = model.onboarding.unitsAreMetric; set(BodyMass.display(kilograms: model.latestWeight?.kilograms ?? 70, metric: metric)) }
        }.tint(Tokens.accent)
    }
    private func set(_ value: Double) {
        let tenths = Int((value * 10).rounded()); whole = tenths / 10; decimal = tenths % 10
    }
    private func save() {
        busy = true; error = nil
        Task {
            do { let message = try await model.logWeight(kilograms: kilograms, toHealth: health); onSaved(message); dismiss() }
            catch { self.error = error.localizedDescription; busy = false }
        }
    }
}

struct MealLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var camera = false
    @State private var photo: UIImage?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var note = ""
    @State private var health = false
    @State private var busy = false
    @State private var estimating = false
    @State private var message: String?
    @State private var started = false
    @State private var estimateTask: Task<Void, Never>?
    @State private var estimateRevision = UUID()
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var loadingPhoto = false
    /// How much of what was photographed was really there, as a multiple of what the
    /// model assumed. Only offered once there is an estimate to correct.
    @State private var portion: Double = 1
    @State private var estimated = false
    let onSaved: (String) -> Void

    private func number(_ text: String) -> Double? {
        FoodNumber.parse(text, decimalSeparator: Locale.current.decimalSeparator ?? ".")
    }
    private func macro(_ text: String) -> Double? {
        FoodNumber.macro(text, decimalSeparator: Locale.current.decimalSeparator ?? ".")
    }
    private var nutrition: MealNutrition? {
        guard let kcal = number(calories), let p = macro(protein),
              let c = macro(carbs), let f = macro(fat) else { return nil }
        let values = MealNutrition(calories: kcal, protein: p, carbs: c, fat: f)
        return values.isValid ? values : nil
    }
    var body: some View {
        NavigationStack {
            mealForm.navigationTitle("").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cancelEstimate(); photoLoadTask?.cancel(); dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
                .fullScreenCover(isPresented: $camera) { MealCamera { image in usePhoto(image); camera = false } onCancel: { camera = false } }
                .onAppear { if !started { started = true; openCamera() } }
                .onChange(of: selectedPhoto) { _, item in
                    guard let item else { return }
                    cancelEstimate()
                    photoLoadTask?.cancel()
                    loadingPhoto = true
                    photoLoadTask = Task {
                        let data = try? await item.loadTransferable(type: Data.self)
                        guard !Task.isCancelled, selectedPhoto == item else { return }
                        loadingPhoto = false
                        if let data, let image = UIImage(data: data) { usePhoto(image) }
                        else { message = "Couldn't open that photo. Try another or enter the meal." }
                    }
                }
                .onDisappear { cancelEstimate(); photoLoadTask?.cancel(); loadingPhoto = false }
        }.tint(Tokens.accent)
    }
    /// A camera product, not a data-entry form.
    ///
    /// The photo is the screen. Everything read off it is laid over the bottom of it as
    /// one number you could read across a room, three macros beside it, and a name you
    /// can type into. Every figure is a text field wearing the same type as the label it
    /// replaced, so correcting the estimate is tapping the thing that is wrong rather
    /// than finding its row in a form.
    private var mealForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    if let message {
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // The name comes first, because it is the field somebody is looking
                    // for. Notes sat here for a few hours today, on the reasoning that
                    // they belong to the reading rather than its result, and two testers
                    // typed their dinner straight into them: the first box under the
                    // photo is the one people fill in, whatever it is labelled. With the
                    // name still empty the Log meal button stayed dead, and both of them
                    // reported that logging a meal does not work.
                    //
                    // What the notes needed was not a better position. It was reaching
                    // the model at all, which Read again does from anywhere on the page.
                    readout.disabled(estimating || busy || loadingPhoto)
                    notes.disabled(estimating || busy || loadingPhoto)
                    Toggle("Save to Apple Health", isOn: $health)
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.textSecondary)
                        .tint(Tokens.accent)
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            logButton
        }
        .background(Tokens.canvas.ignoresSafeArea())
    }

    /// The photo, or the two ways to get one. Sized like a picture rather than like a
    /// row in a list, because it is the evidence for every number under it.
    private var hero: some View {
        ZStack(alignment: .bottom) {
            if let photo {
                // The box decides the size and the picture fills it. Written the other
                // way round, an image told to fill and then given a height claims the
                // width its own aspect ratio wants, and clipping only trims what is
                // drawn, never what was claimed. A landscape photo therefore made this
                // whole screen wider than the phone: the name read "vocado", 320 kcal
                // read "B20", the fat card ran off the right edge. An overlay cannot
                // change what it is laid over, so it cannot do that again.
                Color.clear
                    .frame(maxWidth: .infinity)
                    .frame(height: 300)
                    .overlay { Image(uiImage: photo).resizable().scaledToFill() }
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Tokens.surfaceSunken)
                    .frame(height: 300)
                    .overlay {
                        VStack(spacing: 6) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(Tokens.textSecondary)
                            Text("Photograph the meal")
                                .font(.system(size: 15))
                                .foregroundStyle(Tokens.textSecondary)
                        }
                    }
            }

            // While it is thinking, the coach says so over the picture. A spinner in a
            // list row belongs to a form; this belongs to Jett.
            if estimating || loadingPhoto {
                ThinkingPill(label: estimating ? "Reading the photo" : "Opening photo")
                    .padding(.bottom, 14)
            } else {
                HStack(spacing: 8) {
                    heroButton(photo == nil ? "Camera" : "Retake", "camera") { openCamera() }
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        heroLabel("Library", "photo")
                    }
                }
                .padding(.bottom, 14)
            }
        }
    }

    private func heroButton(_ title: String, _ symbol: String,
                            action: @escaping () -> Void) -> some View {
        Button { Haptics.light(); action() } label: { heroLabel(title, symbol) }
            .buttonStyle(.plain)
    }

    private func heroLabel(_ title: String, _ symbol: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(title).font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(Tokens.textPrimary)
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
    }

    /// Name, one big number, three macros. Each of them editable where it stands.
    private var readout: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("", text: $name, prompt: Text("Name this meal")
                .font(.system(size: 17))
                .foregroundColor(Tokens.textSecondary))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Tokens.textPrimary)
                .textInputAutocapitalization(.sentences)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("0", text: $calories)
                    .font(.system(size: 52, weight: .bold))
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .fixedSize()
                    .accessibilityLabel("Calories")
                Text("kcal")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Tokens.textSecondary)
            }

            HStack(spacing: 8) {
                macroPill("Protein", $protein, Tokens.recoveryHigh)
                macroPill("Carbs", $carbs, Tokens.strainLow)
                macroPill("Fat", $fat, Tokens.sleepLow)
            }

            if estimated { portionRow }
        }
    }

    /// The one correction a photo most needs. Models name food well and misjudge how
    /// much of it there is, and the model's guess is already in the name ("about 1
    /// cup"), so this says how the plate compares to that. Same surface as the macros,
    /// because it is the same kind of thing: a number about this meal you can change.
    private var portionRow: some View {
        HStack(spacing: 4) {
            Text("Portion")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Tokens.textSecondary)
                .textCase(.uppercase)
            Spacer(minLength: 8)
            ForEach(MealPortion.choices, id: \.self) { choice in
                Button { setPortion(choice) } label: {
                    Text(MealPortion.label(choice))
                        .font(.system(size: 17, weight: choice == portion ? .bold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(choice == portion ? Tokens.accent : Tokens.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Self.portionNames[choice] ?? MealPortion.label(choice))
                .accessibilityAddTraits(choice == portion ? .isSelected : [])
            }
        }
        .padding(.leading, 13).padding(.trailing, 6)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static let portionNames: [Double: String] = [
        0.5: "Half the portion", 1: "The portion as estimated",
        1.5: "One and a half times the portion", 2: "Double the portion",
    ]

    /// Scales what is on screen by the ratio, so a macro corrected by hand survives the
    /// tap. Does nothing while a number is not a number, rather than guessing one.
    private func setPortion(_ choice: Double) {
        guard choice != portion, let current = nutrition else { return }
        Haptics.light()
        let next = MealPortion.rescale(current, from: portion, to: choice)
        calories = next.calories.formatted(.number.grouping(.never).precision(.fractionLength(0)))
        protein = next.protein.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
        carbs = next.carbs.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
        fat = next.fat.formatted(.number.grouping(.never).precision(.fractionLength(0...1)))
        portion = choice
    }

    private func macroPill(_ label: String, _ text: Binding<String>, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .textCase(.uppercase)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                TextField("0", text: text)
                    .font(.system(size: 19, weight: .semibold))
                    .monospacedDigit()
                    .keyboardType(.decimalPad)
                    .frame(minWidth: 26)
                    .accessibilityLabel(label)
                Text("g").font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// What the picture does not show, and the way to send it.
    ///
    /// This box did nothing at all. It is an input to the estimate, the estimate runs the
    /// moment a photo arrives, and the box is empty at that moment, so nothing anybody
    /// typed here ever reached the model. It is not saved with the meal either. A field
    /// that silently discards what you write is worse than no field.
    ///
    /// Deliberately still after the photo rather than before it. Nothing stands in front
    /// of the shutter, and until you have seen what the reading got wrong you are
    /// guessing at what to tell it: "half of this" is worth writing once a whole avocado
    /// has come back at 320.
    private var notes: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextField("Portion notes, sauces, anything hidden", text: $note, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...3)
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            if canReadAgain {
                Button { Haptics.light(); estimate() } label: {
                    Label("Read again", systemImage: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Tokens.accent)
                .frame(minHeight: 36)
                .accessibilityHint("Estimate the photo again, using these notes")
            }
        }
    }

    private var canReadAgain: Bool {
        photo != nil && !estimating && !loadingPhoto && !busy
            && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var logButton: some View {
        VStack(spacing: 0) {
            Button { save() } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(Tokens.onAccent) }
                    Text(busy ? "Saving" : "Log meal")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(Tokens.onAction)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(canSave ? Tokens.action : Color.primary.opacity(0.14),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.top, 10)
            .padding(.bottom, blocker == nil ? 8 : 2)
            if let blocker, !busy {
                Text(blocker)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.textSecondary)
                    .padding(.bottom, 8)
            }
        }
        .background(.regularMaterial)
    }

    private var canSave: Bool { blocker == nil }

    /// Why the button is dim, when it is.
    ///
    /// It used to just sit there. A tester ended up with 405,010 g of protein against no
    /// calories, watched Log meal stay dead, and wrote that the app lets numbers mean
    /// nothing and will not tell you. It does reject them, silently, which from the
    /// outside is the same as being broken: two testers reported meal logging as
    /// completely non-functional when the form was refusing one field.
    ///
    /// Nil means nothing is wrong. Anything else is shown under the button.
    private var blocker: String? {
        if busy || estimating || loadingPhoto { return nil }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Give the meal a name."
        }
        guard number(calories) != nil else { return "Add the calories." }
        for (label, text) in [("Protein", protein), ("Carbs", carbs), ("Fat", fat)]
        where macro(text) == nil {
            return "\(label) isn't a number."
        }
        if nutrition == nil { return "Those numbers are outside anything a meal can be." }
        return nil
    }
    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { message = "Camera isn't available here. Choose a photo or enter a meal."; return }
        if AVCaptureDevice.authorizationStatus(for: .video) == .denied || AVCaptureDevice.authorizationStatus(for: .video) == .restricted {
            message = "Camera access is off. Enable Camera in Settings for Jett, choose a photo, or enter a meal."; return
        }
        camera = true
    }
    private func cancelEstimate() {
        estimateTask?.cancel()
        estimateTask = nil
        estimateRevision = UUID()
        estimating = false
    }
    /// Attaching a photo is the instruction, and nothing stands between it and the
    /// reading.
    ///
    /// There used to be a sheet here asking permission to send the photo to DeepSeek by
    /// name. Naming the vendor told people nothing they could act on, and a modal in
    /// front of the one action the screen exists for is a toll booth. What the photo and
    /// notes are used for is written down under Data in Profile, where somebody can read
    /// it without being stopped mid-lunch.
    private func usePhoto(_ image: UIImage) {
        cancelEstimate()
        photo = image
        // Whatever they already typed stays. It used to all be wiped the moment a photo
        // was attached, including the portion notes, which are an input to the estimate
        // and were therefore deleted a line before being read: the note field exists to
        // improve the reading and never reached it. A successful estimate overwrites
        // these anyway, and a failed one now leaves somebody holding what they wrote
        // instead of an empty form.
        message = nil
        // The shutter is the instruction. Nobody photographs their lunch and then wants
        // to be asked whether they meant it.
        estimate()
    }
    private func estimate() {
        guard let photo, !estimating, !loadingPhoto else { return }
        let revision = UUID()
        estimateRevision = revision
        let portionNote = note
        estimating = true; message = nil
        // A new reading replaces the old one, so whatever portion was chosen for the old
        // one no longer means anything.
        estimated = false; portion = 1
        estimateTask = Task {
            defer { if estimateRevision == revision { estimating = false } }
            do {
                let result = try await MealPhotoEstimator.estimate(image: photo, note: portionNote)
                try Task.checkCancellation()
                guard estimateRevision == revision else { return }
                name = result.name
                calories = result.calories.formatted(.number.grouping(.never).precision(.fractionLength(0)))
                protein = result.protein.formatted(.number.grouping(.never).precision(.fractionLength(0)))
                carbs = result.carbs.formatted(.number.grouping(.never).precision(.fractionLength(0)))
                fat = result.fat.formatted(.number.grouping(.never).precision(.fractionLength(0)))
                estimated = true
                // The numbers are already on screen and editable. Saying so would be
                // describing the interface to somebody looking at it.
                message = nil
            } catch is CancellationError {} catch {
                if estimateRevision == revision && !Task.isCancelled { message = error.localizedDescription }
            }
        }
    }
    private func save() {
        guard let nutrition else { return }
        busy = true
        Task {
            do { let result = try await model.logMeal(name: name, nutrition: nutrition, toHealth: health); onSaved(result); dismiss() }
            catch { message = error.localizedDescription; busy = false }
        }
    }
}

private struct MealCamera: UIViewControllerRepresentable {
    let onPhoto: (UIImage) -> Void
    let onCancel: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera
        picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: MealCamera
        init(_ parent: MealCamera) { self.parent = parent }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.onCancel() }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPhoto(image) } else { parent.onCancel() }
        }
    }
}
