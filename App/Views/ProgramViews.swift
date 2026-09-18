import SwiftUI
import SwiftData

/// First run. Name the sessions you actually do and what you're lifting on them —
/// nothing else is asked, because nothing else changes today's call.
struct ProgramSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick a split").sectionHeading()

                ForEach(Starter.all, id: \.name) { starter in
                    Button {
                        install(starter)
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Tokens.recoveryHigh.opacity(0.15))
                                .frame(width: 38, height: 38)
                                .overlay(Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.system(size: 15))
                                    .foregroundStyle(Tokens.recoveryHigh))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(starter.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Tokens.textPrimary)
                                Text(starter.exercises.map(\.0).joined(separator: " · "))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Tokens.textSecondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                        }
                        .bevelCard(padding: 12)
                    }
                    .buttonStyle(.plain)
                }

            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.vertical, 12)
            .padding(.bottom, 88)
        }
    }

    struct Starter {
        let name: String
        /// name, muscle group, working weight, increment
        let exercises: [(String, MuscleGroup, Double, Double)]

        static let all: [Starter] = [
            Starter(name: "Lower body", exercises: [
                ("Back squat", .quads, 225, 10),
                ("Romanian deadlift", .hamstrings, 185, 10),
                ("Leg press", .quads, 360, 10),
            ]),
            Starter(name: "Upper body", exercises: [
                ("Bench press", .chest, 165, 5),
                ("Barbell row", .back, 155, 5),
                ("Overhead press", .shoulders, 105, 5),
            ]),
            Starter(name: "Full body", exercises: [
                ("Back squat", .quads, 225, 10),
                ("Bench press", .chest, 165, 5),
                ("Deadlift", .hamstrings, 275, 10),
            ]),
        ]
    }

    private func install(_ starter: Starter) {
        let existing = (try? context.fetch(FetchDescriptor<WorkoutTemplate>()))?.count ?? 0
        let template = WorkoutTemplate(name: starter.name, order: existing)
        context.insert(template)
        for (index, item) in starter.exercises.enumerated() {
            let exercise = TemplateExercise(name: item.0, muscleGroup: item.1, targetSets: 3,
                                            targetReps: 5, workingWeight: item.2,
                                            increment: item.3, order: index)
            exercise.template = template
            template.exercises.append(exercise)
        }
        try? context.save()
        Task { await model.refresh() }
    }
}

struct TemplateEditorView: View {
    @Bindable var template: WorkoutTemplate

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Name", text: $template.name)
                }
                Section("Exercises") {
                    ForEach(template.orderedExercises) { exercise in
                        ExerciseEditorRow(exercise: exercise)
                    }
                    .onDelete { offsets in
                        let ordered = template.orderedExercises
                        for index in offsets { context.delete(ordered[index]) }
                        try? context.save()
                    }
                    Button("Add exercise") {
                        let exercise = TemplateExercise(name: "New exercise", muscleGroup: .chest,
                                                        workingWeight: 95,
                                                        order: template.exercises.count)
                        exercise.template = template
                        template.exercises.append(exercise)
                        try? context.save()
                    }
                    .tint(Tokens.accent)
                }
                Section {
                    Button("Delete this template", role: .destructive) {
                        context.delete(template)
                        try? context.save()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { try? context.save(); dismiss() }
                        .font(.body.weight(.semibold))
                }
            }
        }
    }
}

struct ExerciseEditorRow: View {
    @Bindable var exercise: TemplateExercise

    var body: some View {
        DisclosureGroup {
            Picker("Muscle group", selection: Binding(
                get: { exercise.muscleGroup },
                set: { exercise.muscleGroupRaw = $0.rawValue })) {
                    ForEach(MuscleGroup.allCases, id: \.self) {
                        Text($0.displayName).tag($0)
                    }
                }
            Stepper(value: $exercise.targetSets, in: 1...10) {
                LabeledContent("Sets", value: "\(exercise.targetSets)")
            }
            Stepper(value: $exercise.targetReps, in: 1...30) {
                LabeledContent("Reps", value: "\(exercise.targetReps)")
            }
            LabeledContent("Working weight") {
                TextField("Weight", value: $exercise.workingWeight,
                          format: .number.precision(.fractionLength(0)))
                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).monospacedDigit()
            }
            Picker("Smallest jump", selection: $exercise.increment) {
                Text("2.5 lb").tag(2.5); Text("5 lb").tag(5.0); Text("10 lb").tag(10.0)
            }
            Stepper(value: $exercise.targetRIR, in: 0...6) {
                LabeledContent("Target RIR", value: "\(exercise.targetRIR)")
            }
            Stepper(value: $exercise.restSeconds, in: 30...420, step: 30) {
                LabeledContent("Rest", value: "\(exercise.restSeconds)s")
            }
        } label: {
            TextField("Exercise", text: $exercise.name)
        }
    }
}
