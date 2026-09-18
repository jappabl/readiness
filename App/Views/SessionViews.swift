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
        ListCard {
            HStack {
                Text(template.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Tokens.textPrimary)
                Spacer()
                if proposals.contains(where: \.changed) {
                    Text("Adjusted")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Tokens.strainLow)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Tokens.strainLow.opacity(0.14), in: Capsule())
                }
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            ForEach(Array(proposals.enumerated()), id: \.offset) { index, proposal in
                Divider().overlay(Tokens.hairline).padding(.leading, 14)
                ProposedExerciseRow(proposal: proposal)
            }
        }
    }
}

struct ProposedExerciseRow: View {
    let proposal: ProposedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.planned.name)
                    .font(.system(size: 15))
                    .foregroundStyle(proposal.isDeferred ? Tokens.textSecondary : Tokens.textPrimary)
                    .strikethrough(proposal.isDeferred, color: Tokens.textSecondary)
                Spacer(minLength: 10)
                Text(proposedText)
                    .font(.system(size: 15)).monospacedDigit()
                    .foregroundStyle(proposal.changed ? Tokens.strainLow : Tokens.textPrimary)
            }
            if proposal.changed {
                Text(proposal.isDeferred ? "Moved to tomorrow" : "was \(originalText)")
                    .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(proposal.isDeferred
            ? "\(proposal.planned.name), moved to tomorrow"
            : "\(proposal.planned.name), \(proposedText)"
              + (proposal.changed ? ", originally \(originalText)" : ""))
    }

    private var proposedText: String {
        proposal.isDeferred
            ? "—"
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
                SkyBackground(signal: .strain)
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

                            Text("Your original session is never overwritten. Either way, the app "
                                 + "records what you chose so it can check itself later.")
                                .font(.system(size: 13)).foregroundStyle(Tokens.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 2)
                        } else {
                            ContentUnavailableView("No session planned", systemImage: "calendar",
                                description: Text("Add a workout template in Train first."))
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
