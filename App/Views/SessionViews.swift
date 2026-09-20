import SwiftUI
import SwiftData

struct PlannedSessionCard: View {
    let template: WorkoutTemplate
    var recommendation: Recommendation? = nil
    var onChange: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onStart: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @Query private var profiles: [UserProfile]
    @State private var expanded = false

    private var isOverridden: Bool { model.todayResponse == .rejected }
    private var metric: Bool { profiles.first?.unitsAreMetric ?? model.onboarding.unitsAreMetric }
    private var hasAdjustment: Bool {
        recommendation?.adjustments.contains(where: { $0 != .proceedAsPlanned }) == true ||
        model.coachAdjustment != nil
    }
    private var proposals: [ProposedExercise] {
        let planned = template.orderedExercises.map(\.plannedExercise)
        let adjustments = isOverridden ? [.proceedAsPlanned] :
            (recommendation?.adjustments ?? [.proceedAsPlanned]) + (model.coachAdjustment.map { [$0] } ?? [])
        return SessionPlanner.apply(adjustments, to: planned)
    }

    var body: some View {
        let allDeferred = !proposals.isEmpty && proposals.allSatisfy(\.isDeferred)
        let visible = expanded ? proposals : Array(proposals.prefix(3))
        ListCard {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name).font(.headline).foregroundStyle(Tokens.textPrimary)
                    Text(allDeferred ? "Moved to tomorrow" :
                            Copy.count(proposals.count, "exercise") + (proposals.contains(where: \.changed) ? " · Adjusted" : ""))
                        .font(.subheadline).foregroundStyle(Tokens.textSecondary)
                }
                Spacer(minLength: 8)
                if let onChange {
                    Button("Change", action: onChange)
                        .font(.subheadline.weight(.medium)).tint(Tokens.accent)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Change workout")
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            ForEach(Array(visible.enumerated()), id: \.offset) { _, proposal in
                Divider().overlay(Tokens.hairline).padding(.leading, 14)
                ProposedExerciseRow(proposal: proposal, metric: metric, showDetails: expanded)
            }
            Divider().overlay(Tokens.hairline)
            HStack {
                Button {
                    expanded.toggle()
                } label: {
                    Label(expanded ? "Less detail" : (proposals.count > 3 ? "All \(proposals.count) exercises" : "Exercise details"),
                          systemImage: expanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline)
                }
                .tint(Tokens.textSecondary)
                Spacer()
                if let onEdit {
                    Button("Edit", action: onEdit).font(.subheadline).tint(Tokens.accent)
                        .accessibilityLabel("Edit session")
                }
            }
            .frame(minHeight: 44).padding(.horizontal, 14)
            if let onStart, !allDeferred {
                Divider().overlay(Tokens.hairline)
                AccessoryRow(symbol: "play.fill", label: "Start workout", tint: Tokens.accent, action: onStart)
            }
            if hasAdjustment {
                Divider().overlay(Tokens.hairline)
                AccessoryRow(symbol: "arrow.uturn.backward",
                             label: isOverridden ? "Use Jett’s adjustment" :
                                (allDeferred ? "Move back to today" : "Keep original plan"),
                             tint: Tokens.textSecondary) {
                    Haptics.decided()
                    model.record(isOverridden ? .accepted : .rejected)
                }
            }
        }
    }
}

struct ProposedExerciseRow: View {
    let proposal: ProposedExercise
    var metric = false
    var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    name
                    Spacer(minLength: 12)
                    prescription
                }
                VStack(alignment: .leading, spacing: 4) { name; prescription }
            }
            if showDetails {
                Text(detail)
                    .font(.caption).foregroundStyle(Tokens.textSecondary)
                if proposal.changed && !proposal.isDeferred {
                    Text("Originally \(proposal.planned.sets) × \(proposal.planned.reps)" + loadText(proposal.planned.workingWeight))
                        .font(.caption).foregroundStyle(Tokens.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(proposal.isDeferred
            ? "\(proposal.planned.name), moved to tomorrow"
            : "\(proposal.planned.name), \(proposal.sets) sets of \(proposal.planned.reps) reps\(loadText(proposal.load)), \(proposal.rir) reps in reserve")
    }

    private var name: some View {
        Text(proposal.planned.name).font(.subheadline)
            .foregroundStyle(proposal.isDeferred ? Tokens.textSecondary : Tokens.textPrimary)
            .strikethrough(proposal.isDeferred)
    }
    private var prescription: some View {
        Text("\(proposal.isDeferred ? proposal.planned.sets : proposal.sets) × \(proposal.planned.reps)" +
             loadText(proposal.isDeferred ? proposal.planned.workingWeight : proposal.load))
            .font(.subheadline).monospacedDigit()
            .foregroundStyle(proposal.changed && !proposal.isDeferred ? Tokens.strainLow : Tokens.textSecondary)
            .strikethrough(proposal.isDeferred)
    }
    private var detail: String {
        proposal.isDeferred ? "Planned for tomorrow" : "\(proposal.rir) reps in reserve"
    }
    private func loadText(_ pounds: Double) -> String {
        guard pounds > 0 else { return "" }
        let displayed = metric ? pounds / 2.2046226218 : pounds
        return " · \(displayed.formatted(.number.precision(.fractionLength(0...1)))) \(metric ? "kg" : "lb")"
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
                                Haptics.committed()
                                model.record(.accepted); dismiss()
                            }
                            Button {
                                Haptics.decided()
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
