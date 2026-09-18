import SwiftUI

/// Four questions. The only thing the app asks you to enter, because it is the only
/// signal no sensor carries.
struct CheckInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var soreness = 3
    @State private var energy = 3
    @State private var stress = 3
    @State private var mood = 3

    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground(signal: .recovery)
                ScrollView {
                    VStack(spacing: 14) {
                        scale("Soreness", value: $soreness, low: "Wrecked", high: "Fresh",
                              symbol: "figure.flexibility")
                        scale("Energy", value: $energy, low: "Flat", high: "Buzzing",
                              symbol: "bolt")
                        scale("Stress", value: $stress, low: "Maxed", high: "Calm",
                              symbol: "wind")
                        scale("Mood", value: $mood, low: "Low", high: "Good",
                              symbol: "face.smiling")

                        Text("This nudges today's call, but it cannot override what your "
                             + "overnight measurements say.")
                            .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)

                        PrimaryButton(label: "Save check-in") {
                            let checkIn = CheckIn(soreness: soreness, energy: energy,
                                                  stress: stress, mood: mood)
                            dismiss()
                            Task { await model.saveCheckIn(checkIn) }
                        }
                        .padding(.top, 2)
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("How are you?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Tokens.textPrimary)
                }
            }
            .onAppear {
                if let existing = model.todayCheckIn {
                    soreness = existing.soreness; energy = existing.energy
                    stress = existing.stress; mood = existing.mood
                }
            }
        }
    }

    private func scale(_ title: String, value: Binding<Int>,
                       low: String, high: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 12))
                    .foregroundStyle(Tokens.recoveryHigh)
                Text(title).font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tokens.textPrimary)
                Spacer()
                Text("\(value.wrappedValue)")
                    .font(.system(size: 20, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(Tokens.recoveryHigh)
            }
            Picker(title, selection: value) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Text(low); Spacer(); Text(high)
            }
            .font(.system(size: 12)).foregroundStyle(Tokens.textSecondary)
        }
        .bevelCard(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value.wrappedValue) out of 5, where 1 is \(low) and 5 is \(high)")
    }
}
