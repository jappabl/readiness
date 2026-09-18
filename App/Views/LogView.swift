import SwiftUI
import SwiftData

/// Deliberately not a workout logger. It records only what was prescribed, because
/// that is the only thing the grading table needs (spec 4.1).
struct LogView: View {
    let prescriptions: [Prescription]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var prescriptionRows: [PrescriptionRow]

    @State private var entries: [String: Entry] = [:]

    struct Entry {
        var asPrescribed = true
        var load: Double
        var reps: Int
        var rir: Int
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Hit everything as prescribed") {
                        for p in prescriptions { entries[p.lift.name]?.asPrescribed = true }
                        save()
                    }
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                } footer: {
                    Text("One tap when the session went to plan. Otherwise adjust below.")
                }

                ForEach(prescriptions, id: \.lift.name) { p in
                    Section(p.lift.name) {
                        Toggle("Hit as prescribed", isOn: binding(for: p).asPrescribed)
                            .tint(Tokens.accent)

                        if !(entries[p.lift.name]?.asPrescribed ?? true) {
                            LabeledContent("Load") {
                                TextField("Load", value: binding(for: p).load,
                                          format: .number.precision(.fractionLength(0)))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .monospacedDigit()
                            }
                            Stepper(value: binding(for: p).reps, in: 0...30) {
                                LabeledContent("Reps",
                                    value: "\(entries[p.lift.name]?.reps ?? p.repTarget)")
                            }
                            Stepper(value: binding(for: p).rir, in: 0...10) {
                                LabeledContent("RIR",
                                    value: "\(entries[p.lift.name]?.rir ?? p.rirTarget)")
                            }
                        } else {
                            LabeledContent("Prescribed") {
                                Text("\(Int(p.prescribedLoad)) lb × \(p.repTarget)")
                                    .monospacedDigit()
                                    .foregroundStyle(Tokens.textSecondary)
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
            .onAppear(perform: seedEntries)
        }
    }

    private func seedEntries() {
        guard entries.isEmpty else { return }
        for p in prescriptions {
            entries[p.lift.name] = Entry(asPrescribed: true, load: p.prescribedLoad,
                                         reps: p.repTarget, rir: p.rirTarget)
        }
    }

    private func binding(for p: Prescription) -> Binding<Entry> {
        Binding(
            get: { entries[p.lift.name] ?? Entry(load: p.prescribedLoad, reps: p.repTarget, rir: p.rirTarget) },
            set: { entries[p.lift.name] = $0 })
    }

    private func save() {
        let today = Calendar.current.startOfDay(for: Date())
        for p in prescriptions {
            let entry = entries[p.lift.name]
                ?? Entry(load: p.prescribedLoad, reps: p.repTarget, rir: p.rirTarget)

            guard let row = prescriptionRows.first(where: {
                $0.liftName == p.lift.name && Calendar.current.isDate($0.date, inSameDayAs: today)
            }) else { continue }

            let existing = (try? context.fetch(FetchDescriptor<OutcomeRow>())) ?? []
            for old in existing where old.prescriptionID == row.id { context.delete(old) }

            context.insert(OutcomeRow(
                prescriptionID: row.id,
                date: today,
                liftName: p.lift.name,
                achievedLoad: entry.asPrescribed ? p.prescribedLoad : entry.load,
                achievedReps: entry.asPrescribed ? p.repTarget : entry.reps,
                achievedRIR: entry.asPrescribed ? p.rirTarget : entry.rir,
                completedAsPrescribed: entry.asPrescribed))
        }
        try? context.save()
        dismiss()
    }
}

private extension Binding where Value == LogView.Entry {
    var asPrescribed: Binding<Bool> {
        Binding<Bool>(get: { wrappedValue.asPrescribed },
                      set: { wrappedValue.asPrescribed = $0 })
    }
    var load: Binding<Double> {
        Binding<Double>(get: { wrappedValue.load }, set: { wrappedValue.load = $0 })
    }
    var reps: Binding<Int> {
        Binding<Int>(get: { wrappedValue.reps }, set: { wrappedValue.reps = $0 })
    }
    var rir: Binding<Int> {
        Binding<Int>(get: { wrappedValue.rir }, set: { wrappedValue.rir = $0 })
    }
}
