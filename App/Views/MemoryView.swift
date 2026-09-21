import SwiftUI

/// The card in Profile, and the page behind it.
///
/// Jett writes to this list without being asked, so the list has to be somewhere a
/// person would actually look — not a row buried between goals and billing. One card
/// that reads as its own thing, and a page that shows the whole list, is how it stays
/// checkable rather than technically visible.

/// What Jett is carrying, at a glance. Deliberately not a settings row: this is the one
/// thing in Profile the app wrote about them rather than the other way round.
struct MemoryCard: View {
    let notes: [CoachMemory.Note]

    private var subtitle: String {
        notes.isEmpty ? "NOTHING YET" : "\(notes.count) THING\(notes.count == 1 ? "" : "S") KEPT"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MEMORY")
                .font(.system(size: 26, weight: .heavy))
                .tracking(1.5)
            Text(subtitle)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 5)
            Spacer(minLength: 34)
            HStack(alignment: .bottom) {
                Text(Self.stamp(notes.last?.written))
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(height: 176)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(
                    colors: [Tokens.accent, Tokens.accent.opacity(0.72)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                // The soft light across the middle is what stops a flat fill reading as
                // a button. It is the only decoration on the card.
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(LinearGradient(
                            colors: [.white.opacity(0.18), .clear, .white.opacity(0.07)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// The date of the newest note, or today when the list is empty, in the fixed-width
    /// form that makes it read as a record rather than a sentence.
    private static func stamp(_ date: Date?) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM.dd.yy"
        return formatter.string(from: date ?? Date())
    }
}

/// Everything Jett has written down.
///
/// The whole reason it is a page: a memory is written without being asked for, so if it
/// were hard to find, one misheard sentence would quietly steer every answer for months
/// and nobody would ever work out why.
struct MemoryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            if model.coachMemory.notes.isEmpty {
                ContentUnavailableView(
                    "Nothing kept yet",
                    systemImage: "brain.head.profile",
                    description: Text("Jett writes something down when it will still matter "
                                      + "in a month. Most conversations add nothing."))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ListCard {
                            // Newest first: a wrong one is almost always a recent one.
                            ForEach(Array(model.coachMemory.notes.reversed().enumerated()),
                                    id: \.element.id) { index, note in
                                if index > 0 {
                                    Divider().overlay(Tokens.hairline).padding(.leading, 16)
                                }
                                row(note)
                            }
                        }
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.vertical, 16)
                }
            }
        }
        .navigationTitle("Memory")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                InfoDot(text: "Jett keeps a few things between conversations. Your scores, "
                        + "sleep and today's session are not on this list, because those "
                        + "are read fresh every time you talk.")
            }
        }
    }

    private func row(_ note: CoachMemory.Note) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(note.text)
                    .font(.system(size: 16))
                    .foregroundStyle(Tokens.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(CoachMemory.age(of: note.written, asOf: Date()))
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.textSecondary)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.decided()
                model.forgetMemory(id: note.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Forget: \(note.text)")
        }
        .padding(.leading, 16)
        .padding(.trailing, 2)
        .padding(.vertical, 10)
    }
}
