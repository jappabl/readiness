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

    /// The metrics the readiness call leans on hardest. Deliberately not all five: a
    /// reveal that lists everything is a table, and a table is what this replaced.
    ///
    /// Not sleep debt, though it is weighted higher than any of these. Every row here is a
    /// value placed against the middle of the user's own distribution, and debt is the one
    /// input in the app deliberately scored against an absolute zero instead, because its
    /// own average ratifies whatever habit produced it. Shown this way it inverted: a
    /// chronic six-hour sleeper's first word from the app about their sleep debt was a
    /// green dot sitting on their own baseline tick, at the cap.
    ///
    /// Sleep *duration* is a different matter and leads, because it does have a meaningful
    /// personal normal and because for a large share of people it is the only thing here
    /// they have. Every one of these needs a watch; without one this screen rendered its
    /// claim over an empty space.
    private static let shown: [MetricKind] = [.hrv, .restingHeartRate, .respiratoryRate]

    private struct Row: Identifiable {
        let id: String
        let title: String
        let unit: String
        let precision: Int
        let value: Double
        let baseline: Double
        let zScore: Double
        /// +1 when higher is better.
        let polarity: Double
        let history: [Double]

        var isFavourable: Bool { zScore * polarity >= 0 }

        /// Only when there is something to say. Three rows all reading "sitting where it
        /// usually does" is the null result printed three times, and the dot already
        /// sitting on the tick says it better than the sentence does.
        var note: String? {
            let brief = MetricNarration.brief(value: value, zScore: zScore, series: history)
            return brief == MetricNarration.unremarkable ? nil : brief
        }
    }

    private func row(id: String, title: String, unit: String, precision: Int,
                     polarity: Double, history: [Double]) -> Row? {
        guard let summary = BaselineSummary.of(history),
              let latest = history.last(where: { $0.isFinite }) else { return nil }
        // The baseline is the middle of their own readings, and the distance from it is
        // measured in their own spread, which is the whole claim being made.
        return Row(id: id, title: title, unit: unit, precision: precision,
                   value: latest, baseline: summary.mean,
                   zScore: (latest - summary.mean) / summary.deviation,
                   polarity: polarity, history: history)
    }

    private var rows: [Row] {
        let sleep = row(id: "sleep", title: "Sleep", unit: "h", precision: 1, polarity: 1,
                        history: series.compactMap(\.sleepHours))
        let metrics = Self.shown.compactMap { kind in
            row(id: kind.rawValue, title: kind.displayName, unit: kind.unit,
                precision: precision(kind), polarity: kind.polarity,
                history: series.compactMap { $0.value(for: kind) })
        }
        // Three rows at most, so the reveal stays a reveal.
        return Array(([sleep].compactMap { $0 } + metrics).prefix(3))
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
                Text(row.title)
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.textSecondary)
                Spacer(minLength: 8)
                Text(row.value.formatted(.number.precision(.fractionLength(row.precision))))
                    .font(.system(size: 19, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textPrimary)
                Text(row.unit)
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.textSecondary)
            }
            RangeBar(z: row.zScore, polarity: row.polarity,
                     tint: row.isFavourable ? Tokens.recoveryHigh : Tokens.strainLow)
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
        case .hrv, .bloodOxygen, .respiratoryRate: return 1
        default: return 0
        }
    }
}
