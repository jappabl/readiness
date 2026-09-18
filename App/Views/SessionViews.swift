import SwiftUI
import SwiftData

/// The planned session beside what the agent proposes. The user's own plan stays visible
/// and is never overwritten.
struct PlannedSessionCard: View {
    let template: WorkoutTemplate
    let recommendation: Recommendation

    var body: some View {
        let proposals = SessionPlanner.apply(recommendation.adjustments,
                                             to: template.orderedExercises.map(\.plannedExercise))
        let allDeferred = !proposals.isEmpty && proposals.allSatisfy(\.isDeferred)

        ListCard {
            header(proposals: proposals, allDeferred: allDeferred)
            ForEach(Array(proposals.enumerated()), id: \.offset) { index, proposal in
                Divider().overlay(Tokens.hairline).padding(.leading, 66)
                ProposedExerciseRow(proposal: proposal)
            }
        }
    }

    /// Icon, name, and the session's status said once — not repeated on every row.
    private func header(proposals: [ProposedExercise], allDeferred: Bool) -> some View {
        let tint = allDeferred ? Tokens.textSecondary : Tokens.strainLow
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(allDeferred ? 0.10 : 0.15))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: symbol)
                        .font(.system(size: 19))
                        .foregroundStyle(tint))
                .saturation(allDeferred ? 0 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if allDeferred {
                        Image(systemName: "clock.badge.checkmark.fill")
                            .font(.system(size: 13))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Tokens.textSecondary, Tokens.surface)
                            .offset(x: 5, y: 4)
                    }
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(template.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(allDeferred ? Tokens.textSecondary : Tokens.textPrimary)
                Text(subtitle(proposals: proposals, allDeferred: allDeferred))
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if proposals.contains(where: \.changed) {
                // The icon carries "moved to tomorrow"; the word is just the when.
                HStack(spacing: 4) {
                    Image(systemName: allDeferred ? "calendar.badge.clock"
                                                  : "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                    Text(allDeferred ? "Tomorrow" : "Adjusted")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(allDeferred ? Tokens.textSecondary : Tokens.strainLow)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background((allDeferred ? Tokens.textSecondary : Tokens.strainLow)
                    .opacity(0.13), in: Capsule())
                .accessibilityLabel(allDeferred ? "Moved to tomorrow" : "Adjusted")
            }
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 12)
    }

    /// The most-worked muscle group stands in for the whole session.
    private var symbol: String {
        let groups = template.orderedExercises.map(\.muscleGroup)
        let counts = Dictionary(groups.map { ($0, 1) }, uniquingKeysWith: +)
        return (counts.max { $0.value < $1.value }?.key ?? .core).symbol
    }

    /// The pill already says Deferred or Adjusted, so the subtitle describes the
    /// session rather than repeating its status — and it fits on one line.
    private func subtitle(proposals: [ProposedExercise], allDeferred: Bool) -> String {
        let sets = proposals.reduce(0) { $0 + (allDeferred ? $1.planned.sets : $1.sets) }
        return Copy.count(proposals.count, "exercise") + " · " + Copy.count(sets, "set")
    }
}

struct ProposedExerciseRow: View {
    let proposal: ProposedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.planned.name)
                    .font(.system(size: 15))
                    .foregroundStyle(proposal.isDeferred ? Tokens.textTertiary : Tokens.textPrimary)
                    .strikethrough(proposal.isDeferred, color: Tokens.textTertiary)
                Spacer(minLength: 10)
                Text(proposedText)
                    .font(.system(size: 15)).monospacedDigit()
                    .foregroundStyle(proposal.isDeferred ? Tokens.textTertiary
                                     : (proposal.changed ? Tokens.strainLow : Tokens.textPrimary))
                    .strikethrough(proposal.isDeferred, color: Tokens.textTertiary)
            }
            if proposal.changed && !proposal.isDeferred {
                Text("was \(originalText)")
                    .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
            }
        }
        .padding(.leading, 66).padding(.trailing, 14).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(proposal.isDeferred
            ? "\(proposal.planned.name), moved to tomorrow"
            : "\(proposal.planned.name), \(proposedText)"
              + (proposal.changed ? ", originally \(originalText)" : ""))
    }

    private var proposedText: String {
        proposal.isDeferred
            ? "\(proposal.planned.sets)×\(proposal.planned.reps) · \(Int(proposal.planned.workingWeight)) lb"
            : "\(proposal.sets)×\(proposal.planned.reps) · \(Int(proposal.load)) lb · RIR \(proposal.rir)"
    }

    private var originalText: String {
        "\(proposal.planned.sets)×\(proposal.planned.reps) · \(Int(proposal.planned.workingWeight)) lb"
    }
}

/// Accept or override. Recording which is what lets the app find out whether its calls
/// were worth making.
struct AdjustSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]

    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground(signal: .recovery)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let template = model.plannedToday(templates: templates),
                           let rec = model.recommendation {
                            CoachCard(message: Copy.call(for: rec,
                                                         gate: model.day?.readiness.gateApplied))
                            PlannedSessionCard(template: template, recommendation: rec)

                            PrimaryButton(label: "Use the adjusted session") {
                                model.record(.accepted); dismiss()
                            }
                            Button {
                                model.record(.rejected); dismiss()
                            } label: {
                                Text("Keep my original plan")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(Tokens.textPrimary)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(Tokens.surface,
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
                            }
                            .buttonStyle(.plain)

                        } else {
                            ContentUnavailableView("No session planned", systemImage: "calendar")
                        }
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Adjust session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.tint(Tokens.textPrimary)
                }
            }
        }
    }
}
