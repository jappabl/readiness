import SwiftUI
import SwiftData

/// The grading record. Predicted against achieved, for every logged session.
/// This screen is the whole point of v0.1 (spec 4.1).
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PrescriptionRow.date, order: .reverse) private var prescriptions: [PrescriptionRow]
    @Query private var outcomes: [OutcomeRow]

    @State private var exportURL: URL?

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            if prescriptions.isEmpty {
                ContentUnavailableView("Nothing graded yet", systemImage: "list.bullet.rectangle",
                                       description: Text("Log a session and it shows up here."))
            } else {
                list
            }
        }
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    exportURL = CSVExport.writeToTemporaryFile(context: context)
                } label: {
                    Label("Export CSV", systemImage: "square.and.arrow.up")
                }
                .accessibilityLabel("Export prediction error as CSV")
            }
        }
        .sheet(item: $exportURL) { url in
            ShareLink(item: url) { Text("Share readiness-export.csv") }
                .presentationDetents([.medium])
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Tokens.cardGap) {
                ForEach(prescriptions) { row in
                    HistoryRowView(row: row,
                                   outcome: outcomes.first { $0.prescriptionID == row.id })
                }
            }
            .padding(.horizontal, Tokens.screenMargin)
            .padding(.top, 8)
            .padding(.bottom, 72)
        }
    }
}

struct HistoryRowView: View {
    let row: PrescriptionRow
    let outcome: OutcomeRow?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(row.date, format: .dateTime.month(.abbreviated).day())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Tokens.textPrimary)
                Spacer()
                Text(AppModel.phrase(for: row.state))
                    .font(.footnote)
                    .foregroundStyle(Tokens.textSecondary)
            }

            Text(row.liftName)
                .font(.footnote)
                .foregroundStyle(Tokens.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                labelled("Prescribed", "\(Int(row.predictedLoad)) lb")
                if let outcome {
                    labelled("Achieved", "\(Int(outcome.achievedLoad)) lb × \(outcome.achievedReps)")
                    labelled("Held", outcome.completedAsPrescribed ? "yes" : "no")
                } else {
                    labelled("Achieved", "—")
                }
            }
        }
        .card()
        .accessibilityElement(children: .combine)
    }

    private func labelled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).sectionHeader()
            Text(value)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
