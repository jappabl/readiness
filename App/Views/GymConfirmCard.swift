import SwiftUI
import MapKit

/// Asked once, after the fact, about a place somebody spent a while and moved in.
///
/// Deliberately not a mid-session interruption: nobody wants a dialog between sets,
/// and the answer is worth just as much an hour later. One question, one tap: the
/// map almost always knows the name, so the common case is confirming it, not typing it.
struct GymConfirmCard: View {
    let visit: GymVisit
    let onConfirm: (String) -> Void
    let onDecline: () -> Void

    @State private var candidates: [String] = []
    @State private var correcting = false
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    private var best: String? { candidates.first }

    var body: some View {
        ListCard {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Tokens.textPrimary)
                    Text(when)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.textSecondary)
                }

                if correcting {
                    correction
                } else {
                    // A small pill, not a full-width button: this is a question worth
                    // answering, not the most important thing on the screen.
                    HStack(spacing: 12) {
                        if let best {
                            pill("Yes") { onConfirm(best) }
                            quietRow(other: "Somewhere else")
                        } else {
                            pill("Name it") { beginCorrecting() }
                            Button("No") { onDecline() }
                                .font(.system(size: 14))
                                .foregroundStyle(Tokens.textSecondary)
                        }
                    }
                }
            }
            .padding(16)
        }
        .task { candidates = await GymNames.nearby(latitude: visit.latitude,
                                                   longitude: visit.longitude) }
    }

    /// Only ever reached by somebody who has already said the top guess is wrong, so
    /// the remaining guesses can be a short list without crowding the first screen.
    private var correction: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(candidates.dropFirst().prefix(2), id: \.self) { name in
                Button { onConfirm(name) } label: {
                    HStack {
                        Text(name).font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Tokens.textPrimary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Tokens.textSecondary)
                    }
                    .padding(.horizontal, 13).padding(.vertical, 11)
                    .background(Tokens.surfaceSunken,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                TextField("Name it", text: $typed)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.words)
                    .focused($fieldFocused)
                    .onSubmit { commit(typed) }
                Button("Save") { commit(typed) }
                    .font(.system(size: 15, weight: .semibold))
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 13).padding(.vertical, 11)
            .background(Tokens.surfaceSunken,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Button("Not a gym") { onDecline() }
                .font(.system(size: 14))
                .foregroundStyle(Tokens.textSecondary)
        }
    }

    private func pill(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tokens.accent)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func quietRow(other: String) -> some View {
        HStack(spacing: 14) {
            Button(other) { beginCorrecting() }
            Text("·").foregroundStyle(Tokens.hairline)
            Button("Not a gym") { onDecline() }
        }
        .font(.system(size: 14))
        .foregroundStyle(Tokens.textSecondary)
    }

    private func beginCorrecting() {
        withAnimation(.snappy(duration: 0.22)) { correcting = true }
        fieldFocused = true
    }

    private func commit(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onConfirm(trimmed)
    }

    private var headline: String {
        // Once they have said the top guess is wrong, keeping it in the question is
        // just arguing with them.
        if correcting { return "Where do you lift?" }
        return best.map { "Do you lift at \($0)?" } ?? "Was that your gym?"
    }

    private var when: String {
        let day = visit.arrival.formatted(.dateTime.weekday(.wide))
        let start = visit.arrival.formatted(date: .omitted, time: .shortened)
        guard let end = visit.departure else { return "\(day), from \(start)" }
        return "\(day), \(start) to \(end.formatted(date: .omitted, time: .shortened))"
    }
}

/// Turns a coordinate into the names of gyms at it, so the question can be
/// "do you lift at EOS?" rather than "do you lift at 37.42, -122.08?".
enum GymNames {
    static func nearby(latitude: Double, longitude: Double) async -> [String] {
        let request = MKLocalPointsOfInterestRequest(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: 120)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.fitnessCenter])
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        // Unique names, nearest first, because chains put three pins on one building.
        var seen = Set<String>()
        return response.mapItems.compactMap { $0.name }.filter { seen.insert($0).inserted }
    }
}
