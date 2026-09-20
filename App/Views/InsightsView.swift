import SwiftUI
import Charts

/// What moved this number, read at a glance.
///
/// Two rewrites got it here, and both are worth recording.
///
/// The first version was Oura's contributor list: a row per input with a signed point
/// attribution, "-17", "-12", "-8". That is a readout for people who already enjoy
/// readouts. Nobody thinks in points, and a column of them is a bill. The arithmetic
/// moved into the bars; the magnitudes still order the rows, so the thing that actually
/// mattered is at the top, it just stopped being something you have to read.
///
/// The second version was full-width rows, which turned out to be permission to write a
/// paragraph in each one. A tile two to a row is not big enough to explain anything, so
/// each one has to earn its space with a number and a shape. The words live behind a tap.
///
/// One screen for all three signals. It reads nothing but `SignalScore`, so an input
/// added to an engine appears here the day it starts counting.
struct InsightsView: View {
    let score: SignalScore

    @Environment(\.dismiss) private var dismiss
    @State private var detail: ScoreContributor?

    private let columns = [GridItem(.flexible(), spacing: 12),
                           GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headline
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(score.contributors, id: \.id) { tile(for: $0) }
                        }
                        if !score.missing.isEmpty { coverage }
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.top, 4)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.tint(Tokens.textPrimary)
                }
            }
            .sheet(item: $detail) { ContributorDetail(contributor: $0, tint: colour($0)) }
        }
    }

    private var title: String {
        switch score.kind {
        case .recovery: return "Your morning"
        case .sleep: return "Last night"
        case .strain: return "Your day"
        }
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(score.value.map { whole($0) } ?? "—")
                    .font(.system(size: 52, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textPrimary)
                if score.value != nil {
                    Text(score.kind == .strain ? "of 21" : "%")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Tokens.textSecondary)
                }
                Spacer(minLength: 8)
                if let band = score.band { BandLabel(band: band) }
            }
            if let lead = score.contributors.first, abs(lead.magnitude) >= 1 {
                Text(verdict(lead))
                    .font(.system(size: 15))
                    .foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - One tile

    /// Symbol, number, bar. No sentence.
    ///
    /// The previous version put two lines of prose under every tile and the screen read
    /// as an essay in a grid. A glyph and a colour carry what those lines carried — a
    /// bed for sleep, an amber flame for a hard hour, an arrow for which side of normal
    /// you landed on — and they carry it without being read. The prose is still there,
    /// behind the tap, for the one row somebody actually wants to understand.
    private func tile(for contributor: ScoreContributor) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: contributor.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(colour(contributor))
                    .frame(height: 20)
                Spacer(minLength: 4)
                if let arrow = direction(contributor) {
                    Image(systemName: arrow)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(colour(contributor))
                }
            }

            Text(contributor.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Tokens.textSecondary)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 9)

            Spacer(minLength: 6)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(headlineValue(contributor))
                    .font(.system(size: 29, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.textPrimary)
                if let unit = unitLabel(contributor) {
                    Text(unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tokens.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.65)

            ComparisonBar(contributor: contributor, tint: colour(contributor))
                .padding(.top, 10)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(.rect)
        .onTapGesture {
            Haptics.light()
            detail = contributor
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(contributor))
        .accessibilityHint("Open for the trend and what this means")
    }

    /// Which side of normal this landed on, as one glyph. Nil when the row has no normal
    /// to be on a side of — a heart rate zone is neither high nor low, it is minutes.
    private func direction(_ contributor: ScoreContributor) -> String? {
        guard let value = contributor.value,
              let comparison = contributor.comparison, comparison > 0 else { return nil }
        switch value / comparison {
        case ..<0.93: return "arrow.down"
        case 1.07...: return "arrow.up"
        default: return "equal"
        }
    }

    /// Percent joins its number; everything else keeps its unit beside it.
    private func headlineValue(_ contributor: ScoreContributor) -> String {
        guard let value = contributor.value else { return "—" }
        return contributor.unit == "%" ? whole(value) + "%" : formatted(value)
    }

    private func unitLabel(_ contributor: ScoreContributor) -> String? {
        contributor.value == nil || contributor.unit.isEmpty || contributor.unit == "%"
            ? nil : contributor.unit
    }

    private func accessibilityLabel(_ contributor: ScoreContributor) -> String {
        var parts = [contributor.title, headlineValue(contributor)]
        if !contributor.unit.isEmpty, contributor.unit != "%" { parts.append(contributor.unit) }
        if let note = contributor.note { parts.append(note) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Words

    private func verdict(_ lead: ScoreContributor) -> String {
        let direction = lead.magnitude > 0 ? "lifted it" : "held it back"
        guard let value = lead.value else {
            return "\(lead.title) did more than anything else today."
        }
        guard let comparison = lead.comparison, comparison > 0 else {
            return "\(lead.title) did most of it — \(measured(value, lead.unit))."
        }
        let side = value < comparison ? "down at" : "up at"
        return "\(lead.title) \(direction) most — \(side) \(measured(value, lead.unit)) "
             + "against \(lead.comparisonLabel ?? "your normal") of \(measured(comparison, lead.unit))."
    }

    // MARK: - Formatting

    private func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// Up to one decimal, dropped when it is a zero. Rounding to whole numbers above ten
    /// put "15 br/min against your normal 14" on screen for 14.6 against 14.2 — a tenth
    /// of a breath shown as a whole one.
    private func formatted(_ value: Double) -> String {
        abs(value) < 1000
            ? value.formatted(.number.precision(.fractionLength(0...1)))
            : value.formatted(.number.precision(.fractionLength(0)))
    }

    /// No space before a percent sign, a space before everything else.
    private func measured(_ value: Double, _ unit: String) -> String {
        if unit.isEmpty { return formatted(value) }
        return unit == "%" ? formatted(value) + unit : formatted(value) + " " + unit
    }

    /// Recovery and sleep colour by how the row is doing. Strain does not have a "doing
    /// well" axis — half an hour near threshold is not good news or bad news, it is hard
    /// — so its tiles colour by effort instead, which is the thing worth seeing at a
    /// glance. Everything blue said nothing.
    private func colour(_ contributor: ScoreContributor) -> Color {
        guard score.kind == .strain else { return colour(contributor.state) }
        guard let reserve = StrainScore.zones.first(where: { $0.id == contributor.id })?.lowerReserve
        else { return Tokens.accent }
        switch reserve {
        case 0.85...: return Tokens.strainDeep
        case 0.75..<0.85: return Tokens.strainLow
        case 0.45..<0.75: return Tokens.accent
        default: return Tokens.textSecondary
        }
    }

    private func colour(_ state: ContributorState) -> Color {
        switch state {
        case .optimal: return Tokens.recoveryHigh
        case .fine: return Tokens.accent
        case .payAttention: return Tokens.strainLow
        }
    }

    // MARK: - Coverage

    private var coverage: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Not counted today")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.textSecondary)
            ForEach(score.missing, id: \.self) { item in
                Text(item)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 2)
    }
}

/// The words a tile is too small to hold, and the trend behind its number.
struct ContributorDetail: View {
    let contributor: ScoreContributor
    var tint: Color = Tokens.accent

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if contributor.history.count > 1 {
                            Chart(Array(contributor.history.enumerated()), id: \.offset) { index, value in
                                LineMark(x: .value("Day", index), y: .value(contributor.title, value))
                                    .foregroundStyle(tint)
                                    .interpolationMethod(.catmullRom)
                                if let comparison = contributor.comparison {
                                    RuleMark(y: .value("Normal", comparison))
                                        .foregroundStyle(Tokens.textTertiary.opacity(0.5))
                                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                                }
                            }
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                            .frame(height: 110)
                            .padding(14)
                            .background(Tokens.surface,
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        Text(contributor.explanation)
                            .font(.system(size: 15))
                            .foregroundStyle(Tokens.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("This is the app's own calculation from what your devices "
                             + "recorded. It is not a clinical measure.")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle(contributor.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.tint(Tokens.textPrimary)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// Where today sits, as a shape rather than a number.
///
/// Fills to the row's own level, which every engine reports on the same 0...1 scale
/// where higher is always better. A tile judged against a normal also marks it, so
/// falling short is a bar stopping before a tick.
///
/// It used to scale by `magnitude`, which was wrong in both directions at once. On
/// strain a magnitude is a contribution, so the biggest bar was the biggest cost — fine.
/// On sleep a magnitude is a loss, so a row that cost nothing drew an empty bar and read
/// as the worst thing on the screen.
struct ComparisonBar: View {
    let contributor: ScoreContributor
    var tint: Color = Tokens.accent

    private let height: CGFloat = 7

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.ringTrack).frame(height: height)
                Capsule()
                    .fill(tint)
                    .frame(width: max(height, width * fill), height: height)
                if hasBaseline {
                    // The baseline itself, so the distance from it carries the message.
                    Capsule()
                        .fill(Tokens.textSecondary.opacity(0.6))
                        .frame(width: 2, height: height + 6)
                        .offset(x: width * Self.baselinePosition - 1)
                }
            }
            .frame(height: height + 6)
        }
        .frame(height: height + 6)
    }

    /// A row judged against a normal gets the normal marked. A heart rate zone has no
    /// normal to mark, so it is a plain bar.
    private var hasBaseline: Bool { (contributor.comparison ?? 0) > 0 }

    /// Where "your normal" sits on the track. Half, because `level` is a share and a
    /// typical reading lands in the middle of its own distribution.
    static let baselinePosition = 0.5

    private var fill: Double {
        min(1, max(0, contributor.level ?? 0))
    }
}

/// The verdict, as a coloured glyph and a word.
///
/// Was a tinted capsule. A background is a container and a container claims to be its
/// own object, so it sat next to the score as a second thing rather than as a label on
/// the first. The symbol and the colour say it, and nothing has to be drawn around them.
struct BandLabel: View {
    let band: ScoreBand

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
            Text(title).font(.system(size: 14, weight: .semibold))
        }
        .foregroundStyle(tint)
    }

    private var title: String {
        switch band {
        case .green: return "Recovered"
        case .yellow: return "Middling"
        case .red: return "Pay attention"
        case .light: return "Light day"
        case .moderate: return "Moderate"
        case .hard: return "Hard"
        case .allOut: return "All out"
        }
    }

    private var symbol: String {
        switch band {
        case .green: return "checkmark.circle.fill"
        case .yellow: return "equal.circle.fill"
        case .red: return "exclamationmark.triangle.fill"
        case .light: return "figure.walk"
        case .moderate: return "figure.run"
        case .hard: return "flame.fill"
        case .allOut: return "bolt.fill"
        }
    }

    private var tint: Color {
        switch band {
        case .green: return Tokens.recoveryHigh
        case .yellow, .light: return Tokens.textSecondary
        case .red, .allOut: return Tokens.strainLow
        case .moderate: return Tokens.accent
        case .hard: return Tokens.strainDeep
        }
    }
}
