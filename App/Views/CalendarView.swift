import SwiftUI
import SwiftData

/// Every day the app has, reachable.
///
/// Replaces a Trends tab. Trends answered a question nobody had asked: four charts of
/// aggregate shapes, while the obvious question, "what happened on Tuesday", had no
/// answer anywhere in the app. A month grid answers it in one tap, and the shape of a
/// month reads off the dots without a chart being drawn at all.
struct CalendarView: View {
    /// Switches to Today, which is now the screen that shows a day.
    var onOpenDay: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context

    @State private var month: Date = Calendar.current.startOfDay(for: Date())
    /// Every logged session, so a month can be drawn without asking the store once per
    /// cell. `hasAnything` fetches all of them each time it is called, which is fine for
    /// one tap and thirty-five table scans for one screen.
    @Query private var sessions: [WorkoutSession]

    private let calendar = Calendar.current

    /// The days in view that have something on them.
    ///
    /// The dot used to mean "this day has a recovery score" and the tap meant "this day
    /// has anything at all", so a day you trained without wearing a watch drew the same
    /// faint dot as a day that never happened, and only one of them answered. A tester
    /// tapped yesterday and the day before, got nothing either time, and reported the
    /// calendar as dead. One meaning now, used for both.
    private var daysWithSomething: Set<Date> {
        var result: Set<Date> = []
        for day in model.series where model.hasAnything(on: day.date) {
            result.insert(calendar.startOfDay(for: day.date))
        }
        for session in sessions where !session.sets.isEmpty {
            result.insert(calendar.startOfDay(for: session.date))
        }
        return result
    }

    var body: some View {
        ZStack {
            Tokens.canvas.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // A month of hollow dots is not a calendar, it is a grid nobody can
                    // read. Until there is a single day with anything on it, say so.
                    if model.series.isEmpty {
                        EmptyStateView(message: "Nothing to look back on yet. Once a few "
                                              + "days are recorded, they show up here.")
                    } else {
                        monthHeader
                        weekdayRow
                        grid
                        key
                    }
                }
                .padding(.horizontal, Tokens.screenMargin)
                .padding(.top, 4)
                .clearsTabBar()
            }
        }
        .navigationTitle("Calendar")
        .toolbarBackground(Tokens.canvas, for: .navigationBar)
    }

    // MARK: - Month

    private var monthHeader: some View {
        HStack {
            Text(month, format: .dateTime.month(.wide).year())
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Tokens.textPrimary)
            Spacer()
            Button { step(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .semibold))
            }
            .padding(.trailing, 14)
            Button { step(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold))
            }
            .disabled(isCurrentMonth)
            .opacity(isCurrentMonth ? 0.3 : 1)
        }
        .foregroundStyle(Tokens.textPrimary)
    }

    private var isCurrentMonth: Bool {
        calendar.isDate(month, equalTo: Date(), toGranularity: .month)
    }

    private func step(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: month) else { return }
        Haptics.light()
        withAnimation(.snappy(duration: 0.2)) { month = next }
    }

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Rotated to the locale's first weekday, so the columns line up with the grid.
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: - Grid

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7),
                  spacing: 6) {
            ForEach(cells, id: \.id) { cell in
                if let date = cell.date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 46)
                }
            }
        }
    }

    private struct Cell: Identifiable { let id: Int; let date: Date? }

    /// Leading blanks so the first of the month lands under its own weekday.
    private var cells: [Cell] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else { return [] }
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let blanks = (0..<offset).map { Cell(id: -$0 - 1, date: nil) }
        let days = range.compactMap { day -> Cell? in
            calendar.date(byAdding: .day, value: day - 1, to: first).map { Cell(id: day, date: $0) }
        }
        return blanks + days
    }

    private func dayCell(_ date: Date) -> some View {
        let recovery = model.recoveryScore(on: date).value
        let isToday = calendar.isDateInToday(date)
        let future = date > Date()
        let has = daysWithSomething.contains(calendar.startOfDay(for: date))
        return VStack(spacing: 4) {
            Text(date, format: .dateTime.day())
                .font(.system(size: 14, weight: isToday ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(future || !has ? Tokens.textTertiary : Tokens.textPrimary)
            // Drawn only where there is something to open. A dot under every past day
            // is an affordance the day cannot honour.
            Circle()
                .fill(dot(recovery))
                .frame(width: 7, height: 7)
                .opacity(recovery == nil ? 0.3 : 1)
                .opacity(has ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background {
            if isToday {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Tokens.textPrimary.opacity(0.07))
            }
        }
        .contentShape(.rect)
        .onTapGesture {
            // Recovery is not the only thing a day can hold. Gating on it meant a day
            // you trained but wore nothing to bed was dead to the touch, and before any
            // health data exists that is every day, which reads as the calendar being
            // broken rather than empty.
            guard !future, has else { return }
            Haptics.light()
            // Rewind the app rather than open a report about the day. Today is the tab
            // that shows a day, and a second screen that also shows one is two answers
            // to the same question.
            model.viewingDate = date
            onOpenDay()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label(date, recovery: recovery))
    }

    /// The same three bands the rings use, so a month of dots reads the same way a day
    /// does. Nothing recorded is a hollow mark, never a red one.
    private func dot(_ recovery: Double?) -> Color {
        guard let recovery else { return Tokens.ringTrack }
        switch ScoreBand.recovery(percent: recovery) {
        case .green: return Tokens.recoveryHigh
        case .yellow: return Tokens.strainLow
        default: return Tokens.alert
        }
    }

    private func label(_ date: Date, recovery: Double?) -> String {
        let day = date.formatted(.dateTime.month(.wide).day())
        guard let recovery else { return "\(day), nothing recorded" }
        return "\(day), recovery \(Int(recovery.rounded()))"
    }

    private var key: some View {
        HStack(spacing: 14) {
            ForEach([("Recovered", Tokens.recoveryHigh),
                     ("Middling", Tokens.strainLow),
                     ("Low", Tokens.alert)], id: \.0) { title, colour in
                HStack(spacing: 5) {
                    Circle().fill(colour).frame(width: 7, height: 7)
                    Text(title).font(.system(size: 12)).foregroundStyle(Tokens.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }
}

/// `Date` is not `Identifiable`, and a sheet needs an identity.
struct DayKey: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

/// One past day, in the same shapes the app uses for today.
struct DayDetailView: View {
    let date: Date

    @Environment(AppModel.self) private var model
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var insight: SignalScore?

    var body: some View {
        NavigationStack {
            ZStack {
                Tokens.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            ring(.recovery, scores.recovery)
                            ring(.sleep, scores.sleep)
                            ring(.strain, scores.strain)
                        }
                        .padding(.vertical, 6)

                        ForEach([scores.recovery, scores.sleep, scores.strain], id: \.kind) { score in
                            if score.value != nil { summaryCard(score) }
                        }
                    }
                    .padding(.horizontal, Tokens.screenMargin)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.tint(Tokens.textPrimary)
                }
            }
            .sheet(item: $insight) { InsightsView(score: $0, date: date) }
        }
    }

    private var scores: (recovery: SignalScore, sleep: SignalScore, strain: SignalScore) {
        model.scores(on: date, context: context)
    }

    private func ring(_ signal: Signal, _ score: SignalScore) -> some View {
        VStack(spacing: 6) {
            RingGauge(signal: signal, percent: score.value.map { max(1, Int($0.rounded())) },
                      lineWidth: 8, figureSize: 20)
                .frame(height: 76)
            Text(signal.title)
                .font(.system(size: 12))
                .foregroundStyle(Tokens.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture {
            guard score.value != nil else { return }
            Haptics.light()
            insight = score
        }
    }

    private func summaryCard(_ score: SignalScore) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title(score.kind)).sectionHeading()
            Text(score.summary)
                .font(.system(size: 14))
                .foregroundStyle(Tokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bevelCard(padding: 14)
    }

    private func title(_ kind: SignalKind) -> String {
        switch kind {
        case .recovery: return "That morning"
        case .sleep: return "That night"
        case .strain: return "That day"
        }
    }
}

extension SignalScore: @retroactive Identifiable {
    public var id: String { kind.rawValue }
}
