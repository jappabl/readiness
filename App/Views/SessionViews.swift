import SwiftUI
import SwiftData

/// The planned session beside what the agent proposes. The user's own plan is always
/// visible and is never overwritten.
struct PlannedSessionCard: View {
    let template: WorkoutTemplate
    let recommendation: Recommendation

    var body: some View {
        let proposals = SessionPlanner.apply(recommendation.adjustments,
                                             to: template.orderedExercises.map(\.plannedExercise))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(template.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Tokens.textPrimary)
                Spacer()
                if proposals.contains(where: \.changed) {
                    Text("Adjusted").qualifier()
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(proposals.enumerated()), id: \.offset) { index, proposal in
                    ProposedExerciseRow(proposal: proposal)
                    if index != proposals.count - 1 {
                        Divider().overlay(Tokens.hairline)
                    }
                }
            }
        }
        .card()
    }
}

struct ProposedExerciseRow: View {
    let proposal: ProposedExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(proposal.planned.name)
                    .font(.subheadline)
                    .foregroundStyle(proposal.isDeferred ? Tokens.textTertiary : Tokens.textPrimary)
                    .strikethrough(proposal.isDeferred)
                Spacer()
                Text(proposedText)
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(proposal.changed ? Tokens.accent : Tokens.textPrimary)
            }
            if proposal.changed {
                Text(proposal.isDeferred ? "Moved to tomorrow" : "was \(originalText)")
                    .qualifier()
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(proposal.isDeferred
            ? "\(proposal.planned.name), moved to tomorrow"
            : "\(proposal.planned.name), \(proposedText)"
              + (proposal.changed ? ", originally \(originalText)" : ""))
    }

    private var proposedText: String {
        proposal.isDeferred
            ? "—"
            : "\(proposal.sets)×\(proposal.planned.reps) @ \(Int(proposal.load)) lb · RIR \(proposal.rir)"
    }

    private var originalText: String {
        "\(proposal.planned.sets)×\(proposal.planned.reps) @ \(Int(proposal.planned.workingWeight)) lb "
        + "· RIR \(proposal.planned.rir)"
    }
}

/// Accept, modify, or reject. Recording which is what lets the app ever find out whether
/// its recommendations were worth making.
struct AdjustSessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let template = model.plannedToday(templates: templates),
                           let rec = model.recommendation {
                            Text(Copy.call(for: rec, gate: model.day?.readiness.gateApplied))
                                .font(.body).foregroundStyle(Tokens.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)

                            PlannedSessionCard(template: template, recommendation: rec)

                            VStack(spacing: 10) {
                                Button {
                                    model.record(.accepted); dismiss()
                                } label: {
                                    Text("Use the adjusted session")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(Tokens.onAccent)
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.borderedProminent).tint(Tokens.accent)

                                Button {
                                    model.record(.rejected); dismiss()
                                } label: {
                                    Text("Keep my original plan")
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered).tint(Tokens.accent)
                            }

                            Text("Your original session is never overwritten. Either way, the app "
                                 + "records what you chose so it can check itself later.")
                                .qualifier().fixedSize(horizontal: false, vertical: true)
                        } else {
                            ContentUnavailableView("No session planned", systemImage: "calendar",
                                description: Text("Add a workout template in Train first."))
                        }
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Adjust session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
