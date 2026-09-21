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
                        if score.coverage != .full { coverage }
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

    /// A ring, not a wall of type.
    ///
    /// This was a 52-point number with a verdict beside it and two lines of prose
    /// underneath: the densest text on a screen whose whole point was to stop being
    /// text. The ring carries the number, its share of the scale and its colour in one
    /// shape, which is the same job done without being read.
    private var headline: some View {
        HStack(alignment: .center, spacing: 18) {
            // The sleep ring shows the night's architecture rather than a plain arc.
            // Same shape, same number in the middle, and it answers the question people
            // actually have about a night: how much of it was deep, how much REM,
            // without spending a single word on it.
            if let night = SleepStages(score: score) {
                SleepStageRing(stages: night, value: score.value)
                    .frame(width: 112, height: 112)
            } else {
                ScoreRing(value: score.value, tint: bandTint, trackHint: score.coverage)
                    .frame(width: 112, height: 112)
            }

            VStack(alignment: .leading, spacing: 7) {
                // No band word. "Pay attention" above a 56 is the number repeated in
                // adjectives, and the ring's own colour already says it without one.
                if let night = SleepStages(score: score) {
                    SleepStageKey(stages: night)
                } else if let lead = score.contributors.first, abs(lead.magnitude) >= 2 {
                    Text(verdict(lead))
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var bandTint: Color {
        guard let band = score.band else { return Tokens.textTertiary }
        switch band {
        case .green: return Tokens.recoveryHigh
        case .yellow, .light: return Tokens.accent
        case .red: return Tokens.alert
        case .moderate: return Tokens.accent
        case .hard: return Tokens.strainLow
        case .allOut: return Tokens.strainDeep
        }
    }

    // MARK: - One tile

    /// Symbol, number, bar. No sentence.
    ///
    /// The previous version put two lines of prose under every tile and the screen read
    /// as an essay in a grid. A glyph and a colour carry what those lines carried: a
    /// bed for sleep, an amber flame for a hard hour, an arrow for which side of normal
    /// you landed on, and they carry it without being read. The prose is still there,
    /// behind the tap, for the one row somebody actually wants to understand.
    private func tile(for contributor: ScoreContributor) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Neutral, always. The symbol says which measurement this is; it does
                // not say how it went. Tinting it as well turned the grid into a
                // fruit bowl and left three things competing to carry one meaning.
                Image(systemName: contributor.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
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

            ComparisonBar(contributor: contributor)
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

    /// How this row went, as one glyph. Never which side of a number it landed on.
    ///
    /// It used to be the ratio of the value to its baseline, which meant the arrow and
    /// the colour were computed from different things and could disagree: solid sleep at
    /// 90% drew a green tile with a down arrow, and every overnight heart rate dip
    /// between 12 and 15% did the same. Direction and colour now say one thing.
    private func direction(_ contributor: ScoreContributor) -> String? {
        contributor.directionSymbol
    }

    /// Percent joins its number; everything else keeps its unit beside it.
    private func headlineValue(_ contributor: ScoreContributor) -> String {
        guard let value = contributor.value else { return "–" }
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
            return "\(lead.title) did most of it: \(measured(value, lead.unit))."
        }
        let side = value < comparison ? "down at" : "up at"
        return "\(lead.title) \(direction) most: \(side) \(measured(value, lead.unit)) "
             + "against \(lead.comparisonLabel ?? "your normal") of \(measured(comparison, lead.unit))."
    }

    // MARK: - Formatting

    private func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }



    /// Up to one decimal, dropped when it is a zero. Rounding to whole numbers above ten
    /// put "15 br/min against your normal 14" on screen for 14.6 against 14.2: a tenth
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
    /// well" axis: half an hour near threshold is not good news or bad news, it is hard.
    /// So its tiles colour by effort instead, which is the thing worth seeing at a
    /// glance. Everything blue said nothing.
    private func colour(_ contributor: ScoreContributor) -> Color {
        guard score.kind == .strain else { return colour(contributor.state) }
        guard let reserve = StrainScore.zones.first(where: { $0.id == contributor.id })?.lowerReserve
        else { return Tokens.accent }
        // Thresholds track `StrainScore.zones`. When the first training zone dropped to
        // 0.40 this ramp still started at 0.45, so "very light effort" (a brisk walk,
        // the thing the change existed to surface) came out the same grey as sitting.
        switch reserve {
        case 0.85...: return Tokens.strainDeep
        case 0.75..<0.85: return Tokens.strainLow
        case 0.35..<0.75: return Tokens.accent
        default: return Tokens.textSecondary
        }
    }

    /// The two states that mean something share their colour with every other breakdown.
    /// An unremarkable row wears the signal's own colour instead — not blue, which was a
    /// third meaning on a screen with two and left every ordinary row looking like an
    /// instruction. It is also what stops the grid reading flat.
    private func colour(_ state: ContributorState) -> Color {
        state == .fine ? signalTint : state.indicatorColour
    }

    private var signalTint: Color {
        switch score.kind {
        case .recovery: return Tokens.recoveryLow
        case .sleep: return Tokens.sleepLow
        case .strain: return Tokens.strainLow
        }
    }

    // MARK: - Coverage

    /// Shown whenever coverage is not full, not only when something is named.
    /// `.buildingBaseline` has an empty `missing` list and used to render nothing at
    /// all, so a day-8 score appeared with exactly the confidence of a day-60 one.
    private var coverage: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(coverageTitle, systemImage: score.coverage == .buildingBaseline
                  ? "hourglass" : "minus.circle")
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

    private var coverageTitle: String {
        switch score.coverage {
        case .buildingBaseline: return "Still learning your normal"
        case .unavailable: return "Nothing recorded yet"
        default: return "Not counted today"
        }
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
/// strain a magnitude is a contribution, so the biggest bar was the biggest cost: fine.
/// On sleep a magnitude is a loss, so a row that cost nothing drew an empty bar and read
/// as the worst thing on the screen.
extension ScoreContributor {
    /// How this row went, as one glyph — never which side of a number it landed on.
    ///
    /// Shared, because `WhyView` grew its own version of this row and drifted: it drew a
    /// bar straight off the z with a fixed polarity, which made sleep debt's dot sit on
    /// the "your normal" tick at zero debt, tinted green, over the sentence "slightly
    /// above baseline" — and left 69% of the track unreachable.
    var directionSymbol: String? {
        switch state {
        case .optimal: return "arrow.up"
        case .payAttention: return "arrow.down"
        case .fine: return nil
        }
    }
}

extension ContributorState {
    var indicatorColour: Color {
        switch self {
        case .optimal: return Tokens.recoveryHigh
        case .payAttention: return Tokens.alert
        case .fine: return Tokens.textSecondary
        }
    }
}

struct ComparisonBar: View {
    let contributor: ScoreContributor
    /// Deliberately one neutral colour.
    ///
    /// Tinting the bar as well meant three things on a tile were saying the same thing,
    /// and a grid of coloured bars is a wall of colour that draws the eye everywhere and
    /// therefore nowhere. The bar carries how much; the arrow carries how it went.
    var tint: Color = Tokens.textPrimary.opacity(0.55)

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

    /// Only rows whose level really is a percentile of the sleeper's own history get a
    /// "normal" tick at the halfway mark.
    ///
    /// It used to be drawn for anything with a comparison, but several rows report level
    /// as a share of a target rather than a percentile (time asleep against need, the
    /// heart rate dip against a strong one), and on those, half the bar is not the
    /// normal. The tick was claiming a fact the bar could not support.
    private var hasBaseline: Bool { contributor.comparisonLabel != nil }

    /// Where "your normal" sits on the track. Half, because a typical reading lands in
    /// the middle of its own distribution.
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
        case .red: return Tokens.alert
        case .allOut: return Tokens.strainDeep
        case .moderate: return Tokens.accent
        case .hard: return Tokens.strainDeep
        }
    }
}

/// The score as a ring: the number, its share of the scale, and its colour in one shape.
///
/// All three signals are percentages now, so one ring serves all of them. Floored at a
/// sliver of arc when there is a score at all, because an empty ring and a ring at three
/// percent are different facts and should not draw the same.
struct ScoreRing: View {
    let value: Double?
    var tint: Color = Tokens.accent
    var trackHint: ScoreCoverage = .full

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    private var fraction: Double {
        guard let value else { return 0 }
        return Swift.max(0.02, Swift.min(1, value / 100))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Tokens.ringTrack, style: StrokeStyle(lineWidth: 11, lineCap: .round))
            // A thin baseline is drawn as a dashed remainder rather than a solid one, so
            // the picture says "still learning" without needing the words underneath.
            if trackHint == .buildingBaseline {
                Circle()
                    .trim(from: fraction, to: 1)
                    .stroke(tint.opacity(0.35),
                            style: StrokeStyle(lineWidth: 11, lineCap: .butt, dash: [1.6, 3.6]))
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .trim(from: 0, to: drawn || reduceMotion ? fraction : 0)
                .stroke(tint, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text(value.map { Swift.max(1, $0.rounded()).formatted(.number.precision(.fractionLength(0))) } ?? "–")
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.65)) { drawn = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(value.map { "\(Int($0.rounded())) percent" } ?? "No score yet")
    }
}

/// The four parts of a night, read straight off a sleep `SignalScore`.
///
/// Light is what is left once deep, REM and awake are taken out of the total. The
/// engine never reports it separately because nothing scores it, but it is most of a
/// night and leaving it out of the picture would make the other three look enormous.
struct SleepStages {
    let deep: Double
    let rem: Double
    let light: Double
    let awake: Double

    init?(score: SignalScore) {
        guard score.kind == .sleep,
              let asleep = score.contributor(SleepScore.durationContributorID)?.value,
              asleep > 0,
              let deep = score.contributor("deep")?.value,
              let rem = score.contributor("rem")?.value else { return nil }
        // No scaling here, and no denominator of the view's own. The engine publishes the
        // stage hours it actually scored, already reconciled against the night when two
        // devices between them staged more of it than it held.
        //
        // Deriving it again here was the bug, and the previous attempt at fixing it was a
        // no-op: core was *reconstructed* as asleep - deep - rem rather than read, which
        // makes the denominator identically max(deep + rem, asleep). That engages only
        // when deep and REM alone exceed the whole night — a sixth of the nights the
        // engine scales — so on the rest the ring drew, and the key printed, up to an hour
        // of deep sleep that did not happen.
        self.deep = deep
        self.rem = rem
        self.awake = score.contributor("awake")?.value ?? 0
        self.light = max(0, asleep - deep - rem)
    }

    /// Below this, being awake is stirring rather than an awakening, and listing it
    /// gives a normal night a row about nothing.
    static let minimumAwakeHours = 0.25

    var countedAwake: Double { awake >= Self.minimumAwakeHours ? awake : 0 }

    var total: Double { deep + rem + light + countedAwake }

    /// Drawn deepest first, so the ring reads from the bottom of the night outward.
    var parts: [(id: String, title: String, hours: Double, colour: Color)] {
        [("deep", "Deep", deep, Tokens.sleepDeep),
         ("rem", "REM", rem, Tokens.sleepLow),
         ("light", "Light", light, Tokens.sleepHigh),
         // Not the track colour: awake drawn in the same grey as the empty ring was
         // invisible, which is the one stage somebody is looking for.
         ("awake", "Awake", countedAwake, Tokens.textTertiary.opacity(0.55))]
    }
}

/// A ring divided into the night's stages, with the score in the middle.
struct SleepStageRing: View {
    let stages: SleepStages
    let value: Double?
    var lineWidth: CGFloat = 11
    var figureSize: CGFloat = 32

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn = false

    var body: some View {
        ZStack {
            Circle().stroke(Tokens.ringTrack, style: StrokeStyle(lineWidth: lineWidth))

            // Each stage is an arc whose length is its share of the night, laid end to
            // end around the circle. A one-degree gap keeps two dark stages apart.
            ForEach(Array(segments.enumerated()), id: \.element.id) { _, segment in
                Circle()
                    .trim(from: segment.start, to: drawn || reduceMotion ? segment.end : segment.start)
                    .stroke(segment.colour, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }

            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value.map { Swift.max(1, $0.rounded()).formatted(.number.precision(.fractionLength(0))) } ?? "–")
                    .font(.system(size: figureSize, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Tokens.textPrimary)
        }
        .task {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.7)) { drawn = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private struct Segment { let id: String; let start: Double; let end: Double; let colour: Color }

    private var segments: [Segment] {
        let total = stages.total
        guard total > 0 else { return [] }
        var cursor = 0.0
        return stages.parts.compactMap { part in
            let share = part.hours / total
            guard share > 0.001 else { return nil }
            let start = cursor
            cursor += share
            // A hair of gap, taken off the end so the arcs still add to the whole.
            return Segment(id: part.id, start: start,
                           end: Swift.max(start, cursor - 0.004), colour: part.colour)
        }
    }

    private var accessibility: String {
        let parts = stages.parts
            .filter { $0.hours > 0 }
            .map { "\($0.title) \($0.hours.formatted(.number.precision(.fractionLength(0...1)))) hours" }
        return ([value.map { "Sleep \(Int($0.rounded())) percent" }].compactMap { $0 } + parts)
            .joined(separator: ", ")
    }
}

/// What each colour in the ring is. The one place a word earns its keep on this screen.
///
/// A ring shows the shape of a night and withholds its numbers, which is half an answer.
/// Beside a small ring the key stacks; under a big one it sits in two columns.
struct SleepStageKey: View {
    let stages: SleepStages
    var columns: Int = 1

    private var shown: [(id: String, title: String, hours: Double, colour: Color)] {
        stages.parts.filter { $0.hours > 0.01 }
    }

    var body: some View {
        Group {
            if columns > 1 {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10,
                                                             alignment: .leading),
                                         count: columns),
                          alignment: .leading, spacing: 8) {
                    ForEach(shown, id: \.id) { entry($0) }
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(shown, id: \.id) { entry($0) }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func entry(_ part: (id: String, title: String, hours: Double, colour: Color)) -> some View {
        HStack(spacing: 6) {
            Circle().fill(part.colour).frame(width: 7, height: 7)
            Text(part.title)
                .font(.system(size: 13))
                .foregroundStyle(Tokens.textSecondary)
            Text(part.hours.formatted(.number.precision(.fractionLength(0...1))) + " h")
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Tokens.textPrimary)
            Spacer(minLength: 0)
        }
    }
}
