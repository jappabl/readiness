import SwiftUI
import SwiftData

/// Deliberately not a workout logger. It records only what was prescribed, because
/// that is the only thing the grading table needs (spec 4.1).
struct LogView: View {
    let prescriptions: [Prescription]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var prescriptionRows: [PrescriptionRow]

    @State private var entries: [Entry] = []

    struct Entry: Identifiable {
        let id = UUID()
        let prescription: Prescription
        var asPrescribed: Bool = true
        var load: Double
        var reps: Int
        var rir: Int

        init(prescription: Prescription) {
            self.prescription = prescription
            self.load = prescription.prescribedLoad
            self.reps = prescription.repTarget
            self.rir = prescription.rirTarget
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Hit everything as prescribed") {
                        for index in entries.indices { entries[index].asPrescribed = true }
                        save()
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                } footer: {
                    Text("One tap when the session went to plan. Otherwise adjust below.")
                }

                ForEach($entries) { $entry in
                    Section(entry.prescription.lift.name) {
                        Toggle("Hit as prescribed", isOn: $entry.asPrescribed)
                            .tint(Tokens.accent)

                        if entry.asPrescribed {
                            LabeledContent("Prescribed") {
                                Text("\(Int(entry.prescription.prescribedLoad)) lb × \(entry.prescription.repTarget)")
                                    .monospacedDigit()
                                    .foregroundStyle(Tokens.textSecondary)
                            }
                        } else {
                            LabeledContent("Load") {
                                TextField("Load", value: $entry.load,
                                          format: .number.precision(.fractionLength(0)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                            }
                            Stepper(value: $entry.reps, in: 0...30) {
                                LabeledContent("Reps", value: "\(entry.reps)")
                            }
                            Stepper(value: $entry.rir, in: 0...10) {
                                LabeledContent("RIR", value: "\(entry.rir)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Log session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.font(.body.weight(.semibold))
                }
            }
            .onAppear {
                guard entries.isEmpty else { return }
                entries = prescriptions.map(Entry.init)
            }
        }
    }

    private func save() {
        let today = Calendar.current.startOfDay(for: Date())
        for entry in entries {
            guard let row = prescriptionRows.first(where: {
                $0.liftName == entry.prescription.lift.name
                    && Calendar.current.isDate($0.date, inSameDayAs: today)
            }) else { continue }

            let existing = (try? context.fetch(FetchDescriptor<OutcomeRow>())) ?? []
            for old in existing where old.prescriptionID == row.id { context.delete(old) }

            context.insert(OutcomeRow(
                prescriptionID: row.id,
                date: today,
                liftName: entry.prescription.lift.name,
                achievedLoad: entry.asPrescribed ? entry.prescription.prescribedLoad : entry.load,
                achievedReps: entry.asPrescribed ? entry.prescription.repTarget : entry.reps,
                achievedRIR: entry.asPrescribed ? entry.prescription.rirTarget : entry.rir,
                completedAsPrescribed: entry.asPrescribed))
        }
        try? context.save()
        dismiss()
    }
}
