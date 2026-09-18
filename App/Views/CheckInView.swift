import SwiftUI

/// Four questions, one screen, native controls. This is the only thing the app asks the
/// user to type, because it is the only signal no sensor carries.
struct CheckInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var soreness = 3
    @State private var energy = 3
    @State private var stress = 3
    @State private var mood = 3

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    scale("Soreness", value: $soreness, low: "Wrecked", high: "Fresh")
                    scale("Energy", value: $energy, low: "Flat", high: "Buzzing")
                    scale("Stress", value: $stress, low: "Maxed", high: "Calm")
                    scale("Mood", value: $mood, low: "Low", high: "Good")
                } footer: {
                    Text("This nudges today's call, but it cannot override what your "
                         + "overnight measurements say.")
                }
            }
            .navigationTitle("How are you?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let checkIn = CheckIn(soreness: soreness, energy: energy,
                                              stress: stress, mood: mood)
                        dismiss()
                        Task { await model.saveCheckIn(checkIn) }
                    }
                    .font(.body.weight(.semibold))
                }
            }
            .onAppear {
                if let existing = model.todayCheckIn {
                    soreness = existing.soreness
                    energy = existing.energy
                    stress = existing.stress
                    mood = existing.mood
                }
            }
        }
    }

    private func scale(_ title: String, value: Binding<Int>,
                       low: String, high: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.body).foregroundStyle(Tokens.textPrimary)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.body).monospacedDigit()
                    .foregroundStyle(Tokens.textSecondary)
            }
            Picker(title, selection: value) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Text(low).qualifier()
                Spacer()
                Text(high).qualifier()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value.wrappedValue) out of 5, where 1 is \(low) and 5 is \(high)")
    }
}
