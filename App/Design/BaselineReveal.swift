import SwiftUI

/// The end of onboarding, where Jett shows somebody their own normal.
///
/// The first version drew all 180 readings as a scatter with a band through it. It was
/// a cloud, and the only thing it could conclude was "today sits inside your range",
/// which is the null result written out at length.
///
/// This is the shape the rest of the app already uses and the shape every other
/// recovery app converges on: one number, one position against your own baseline, one
/// short verdict. `RangeBar` and `MetricNarration` both already existed and are both
/// already tested; this is a stack of them rather than anything new.
struct BaselineReveal: View {

    /// Series, oldest first.
    let series: [DailyPhysiology]

    /// The three the readiness call leans on hardest. Deliberately not all five: a
    /// reveal that lists everything is a table, and a table is what this replaced.
    private static let shown: [MetricKind] = [.hrv, .restingHeartRate, .sleepDebt]

    private struct Row: Identifiable {
        let id: MetricKind
        let reading: MetricReading
        let history: [Double]
        /// Only when there is something to say. Three rows all reading "sitting where
        /// it usually does" is the null result printed three times, and the dot already
        /// sitting on the tick says it better than the sentence does.
        var note: String? {
            let brief = MetricNarration.brief(reading: reading, series: history)
            return brief == MetricNarration.unremarkable ? nil : brief
        }
    }

    private var rows: [Row] {
        Self.shown.compactMap { kind in
            let history = series.compactMap { $0.value(for: kind) }
            guard let summary = BaselineSummary.of(history),
                  let latest = history.last(where: { $0.isFinite }) else { return nil }
            // The baseline is the middle of their own readings, and the distance from
            // it is measured in their own spread, which is the whole claim being made.
            let reading = MetricReading(kind: kind,
                                        value: latest,
                                        baseline: summary.mean,
                                        zScore: (latest - summary.mean) / summary.deviation,
                                        sampleCount: summary.count)
            return Row(id: kind, reading: reading, history: history)
        }
    }

    var body: some View {
        let rows = rows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ListCard {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                        line(row)
                    }
                }
            }
        }
    }

    private func line(_ row: Row) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.reading.kind.displayName)
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.textSecondary)
                Spacer(minLength: 8)
                Text(row.reading.value.formatted(
                    .number.precision(.fractionLength(precision(row.reading.kind)))))
                    .font(.system(size: 19, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textPrimary)
                Text(row.reading.kind.unit)
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.textSecondary)
            }
            RangeBar(z: row.reading.zScore,
                     polarity: row.reading.kind.polarity,
                     tint: row.reading.isFavourable ? Tokens.recoveryHigh : Tokens.strainLow)
            // Derived, never written by a model, so it cannot claim something the
            // numbers do not show.
            if let note = row.note {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func precision(_ kind: MetricKind) -> Int {
        switch kind {
        case .hrv, .bloodOxygen, .sleepDebt: return 1
        default: return 0
        }
    }
}
