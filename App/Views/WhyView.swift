import SwiftUI

/// The evidence behind today's call, for the morning the app disagrees with how you feel.
///
/// Read top to bottom it answers three questions in order: what should I do, what is
/// that based on, and what could it be missing. The model's internals (weights,
/// points, the composite total) are deliberately not on this screen. They explain how
/// the arithmetic works, not why today is what it is, and they crowded out the part
/// that does.
struct WhyView: View {
    let day: AssembledDay
    let recommendation: Recommendation

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var editingCheckIn = false

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        verdict
                        evidence
                        uncertainty
                        provenance
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
            .sheet(isPresented: $editingCheckIn) { CheckInView() }
            .navigationTitle("Why")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Tokens.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 16, weight: .semibold)).tint(Tokens.accent)
                }
            }
        }
    }

    // MARK: - The call, resting on the plan

    /// The same layered pair as Today: two surfaces, the top one shadowing the one
    /// beneath, so the call reads as sitting *on* the plan rather than beside it.
    private var verdict: some View {
        VStack(spacing: -18) {
            call.zIndex(1)
            plan
        }
    }

    /// The one recovery score there is.
    ///
    /// This screen used to compute its own: the composite run through a standard normal
    /// CDF as though its spread were 1.0, which is the transfer `RecoveryScore` exists to
    /// replace, and with no gate ceiling at all. So the two rings disagreed by up to seven
    /// points on an ordinary morning and by **82** under the illness gate: Today showed a
    /// red 8, and tapping it to ask why showed a green 90 beside this screen's own headline
    /// "Recover". A second hand-maintained breakdown of the same result was always going to
    /// end up describing a different model; there is one now.
    /// Read off the model rather than recomputed here, so this screen cannot drift again.
    /// Recomputing it needed every input the model feeds in: the trailing history, and
    /// now the night, for somebody whose only shared stream is sleep, and a call site
    /// that has to remember those is a call site that will eventually forget one.
    private var score: SignalScore { model.recoveryScore }

    private var readinessPercent: Int? {
        score.value.map { max(1, Int($0.rounded())) }
    }

    private var call: some View {
        HStack(spacing: 16) {
            RingGauge(signal: .recovery, percent: readinessPercent,
                      lineWidth: 9, figureSize: 22)
                .frame(width: 74, height: 74)
            VStack(alignment: .leading, spacing: 4) {
                Text(Copy.headline(for: recommendation.state))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Tokens.textPrimary)
                Text(Copy.call(for: recommendation, gate: day.readiness.gateApplied))
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.cardRadius,
                                                         style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 8, x: 0, y: 4)
    }

    private var plan: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The plan").microLabel()
            ForEach(recommendation.adjustments, id: \.self) { adjustment in
                HStack(spacing: 12) {
                    // Neutral, and no disc. These are the steps of one instruction, not
                    // four things competing for attention, and a tinted capsule behind a
                    // glyph is the house rule this screen was still breaking.
                    Image(systemName: Copy.symbol(for: adjustment))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.textPrimary)
                        .frame(width: 24)
                    Text(Copy.describe(adjustment))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Tokens.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .padding(.top, 31)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.surface, in: RoundedRectangle(cornerRadius: Tokens.cardRadius,
                                                         style: .continuous))
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 2)
        .shadow(color: .black.opacity(0.03), radius: 2, x: 0, y: 1)
    }

    // MARK: - Evidence

    /// Biggest mover first, whichever way it moved: on a good day the reason is a
    /// metric that went up. Already ordered that way, and with the gate's own row included,
    /// which this screen previously left out entirely.
    private var ranked: [ScoreContributor] { score.contributors }

    private var evidence: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What it read").sectionHeading()
            ListCard {
                ForEach(Array(ranked.enumerated()), id: \.element.id) { index, contribution in
                    if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                    row(for: contribution)
                }
                Divider().overlay(Tokens.hairline).padding(.leading, 14)
                felt
            }
        }
    }

    /// What the user reported this morning, shown here rather than on Today: it is an
    /// input to the decision, and repeating someone's own answer back to them anywhere
    /// else is just an echo.
    private var felt: some View {
        Button { Haptics.light(); editingCheckIn = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tokens.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Tokens.textSecondary.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("How you felt")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Tokens.textPrimary)
                    Text(feltNote)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.textSecondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint(model.todayCheckIn == nil ? "Check in" : "Edit your check-in")
    }

    private var feltNote: String {
        guard let checkIn = model.todayCheckIn else { return "Not answered yet" }
        let mean = Double(checkIn.soreness + checkIn.energy + checkIn.stress + checkIn.mood) / 4
        let shift = RecommendationEngine.checkInShift(checkIn)
        let word: String
        switch mean {
        case ..<1.75: word = "Rough"
        case ..<2.5:  word = "Low"
        case ..<3.5:  word = "Okay"
        case ..<4.25: word = "Good"
        default:      word = "Strong"
        }
        switch shift {
        case 0.05...:     return "\(word), nudged the call up"
        case ..<(-0.05):  return "\(word), nudged the call down"
        default:          return "\(word), didn't move the call"
        }
    }

    /// One input, in the same shapes the rest of the app uses for a contributor.
    ///
    /// The bar is `ComparisonBar` over the contributor's own `level` rather than a
    /// `RangeBar` over the raw z with a fixed polarity. That mattered most for sleep debt,
    /// which is one-sided: the old row could only place its dot between 0.31 and 0.50 of
    /// the track, so 69% of the bar was unreachable, the "your normal" tick marked the
    /// *best* case rather than the middle, and owing nothing drew a green dot sitting on
    /// that tick under the words "slightly above baseline".
    private func row(for contributor: ScoreContributor) -> some View {
        let kind = MetricKind(rawValue: contributor.id)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                // Neutral, and no disc behind it. The symbol says which measurement this
                // is; the arrow says how it went.
                Image(systemName: contributor.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
                    .frame(width: 22)
                Text(contributor.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Tokens.textPrimary)
                if let kind {
                    InfoButton(kind)
                        .padding(.horizontal, -9)
                }
                Spacer(minLength: 8)
                if let arrow = contributor.directionSymbol {
                    Image(systemName: arrow)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(contributor.state.indicatorColour)
                }
                if let value = contributor.value {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(number(value) + (contributor.unit == "%" ? "%" : ""))
                            .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(Tokens.textPrimary)
                        if contributor.unit != "%" {
                            Text(contributor.unit)
                                .font(.system(size: 12))
                                .foregroundStyle(Tokens.textSecondary)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ComparisonBar(contributor: contributor)
                if let note = phrase(contributor) {
                    Text(note)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.textSecondary)
                }
            }
            .padding(.leading, 32)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    /// The engine's own sentence where it has one, and otherwise what the reading was
    /// judged against. Never a phrase derived from the z here: that was how this screen
    /// came to describe a different model from the one doing the scoring.
    private func phrase(_ contributor: ScoreContributor) -> String? {
        if let note = contributor.note { return note }
        guard let comparison = contributor.comparison, let label = contributor.comparisonLabel
        else { return nil }
        let sentenceCased = label.prefix(1).uppercased() + label.dropFirst()
        let unit = contributor.unit == "%" ? "%" : " " + contributor.unit
        return "\(sentenceCased) is \(number(comparison))\(unit)"
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
    }

    // MARK: - Limits

    @ViewBuilder
    private var uncertainty: some View {
        if !recommendation.uncertainty.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("What it can't see").sectionHeading()
                ListCard {
                    ForEach(Array(recommendation.uncertainty.enumerated()), id: \.element) { index, note in
                        if index > 0 { Divider().overlay(Tokens.hairline).padding(.leading, 14) }
                        Text(note)
                            .font(.system(size: 14))
                            .foregroundStyle(Tokens.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                }
            }
        }
    }

    private var provenance: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let deviation = day.wristTemperatureDeviationC {
                Text(temperatureLine(deviation))
                    .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Model \(recommendation.modelVersion) · \(Copy.count(day.daysOfHistory, "day")) · "
                 + "confidence \(recommendation.confidence.rawValue)")
                .font(.system(size: 12)).foregroundStyle(Tokens.textTertiary)
        }
        .padding(.horizontal, 2)
    }

    private func temperatureLine(_ deviation: Double) -> String {
        let value = deviation.formatted(.number.precision(.fractionLength(2)).sign(strategy: .always()))
        let base = "Wrist temperature \(value) °C from baseline"
        guard day.readiness.gateApplied == .elevatedWristTemperature else { return base + "." }
        return base + ", above the illness threshold, which capped today."
    }
}
