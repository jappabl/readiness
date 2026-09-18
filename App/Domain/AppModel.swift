import Foundation
import HealthKit
import SwiftData
import SwiftUI

@Observable
@MainActor
final class AppModel {

    enum Phase {
        case loading
        case needsLifts
        case ready
        case failed(String)
    }

    var phase: Phase = .loading
    var day: AssembledDay?
    var prescriptions: [Prescription] = []
    var seededSampleCount: Int?

    private let healthKit = HealthKitSource()
    private var context: ModelContext?

    static let historyDays = 180

    func attach(_ context: ModelContext) { self.context = context }

    // MARK: - Load

    /// Spec AC1: a readiness state and a prescribed session inside 60 seconds of a
    /// fresh install, with no calibration wait. Everything already on the device is used.
    func refresh() async {
        guard let context else { return }
        phase = .loading

        do {
            guard HealthKitSource.isAvailable else { throw HealthSourceError.unavailable }

            // One prompt, covering read and (on the simulator) write.
            #if targetEnvironment(simulator)
            try await healthKit.requestAuthorization(alsoShare: HealthKitSeeder.shareTypes)
            #else
            try await healthKit.requestAuthorization()
            #endif

            // A fresh simulator has a real but empty HealthKit store. Seed it so the
            // genuine read path is exercised rather than bypassed.
            #if targetEnvironment(simulator)
            if await !healthKit.hasAnyData() {
                seededSampleCount = try? await HealthKitSeeder.seed(days: Self.historyDays,
                                                                    into: healthKit)
            }
            #endif

            let series = try await healthKit.dailySeries(days: Self.historyDays)
            let usable = series.filter { $0.hrvSDNN != nil || $0.restingHeartRate != nil }

            guard let assembled = DayAssembler.assemble(series: usable), usable.count >= 2 else {
                phase = .failed("No health history found yet. Wear your watch overnight and come back.")
                return
            }

            day = assembled
            persist(assembled, into: context)

            let lifts = (try? context.fetch(
                FetchDescriptor<LiftConfig>(sortBy: [SortDescriptor(\.order)]))) ?? []
            guard !lifts.isEmpty else { phase = .needsLifts; return }

            prescriptions = lifts.map {
                PrescriptionEngine.prescribe(lift: $0.lift,
                                             state: assembled.readiness.state,
                                             multiDayTrendPresent: assembled.multiDayTrendPresent)
            }
            persistPrescriptions(for: assembled, into: context)
            phase = .ready

        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func startBackgroundDelivery() {
        healthKit.startBackgroundDelivery { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
    }

    // MARK: - Persistence

    private func persist(_ assembled: AssembledDay, into context: ModelContext) {
        let date = Calendar.current.startOfDay(for: assembled.date)

        let existing = (try? context.fetch(FetchDescriptor<ReadinessRow>())) ?? []
        for row in existing where Calendar.current.isDate(row.date, inSameDayAs: date) {
            context.delete(row)
        }
        context.insert(ReadinessRow(date: date, result: assembled.readiness))

        let lowConfidence = assembled.readiness.confidence == .low
        for reading in assembled.readings {
            context.insert(DailyMetricRow(date: date, kind: reading.kind, value: reading.value,
                                          baseline: reading.baseline, zScore: reading.zScore,
                                          sampleCount: reading.sampleCount,
                                          lowConfidence: lowConfidence))
        }
        try? context.save()
    }

    private func persistPrescriptions(for assembled: AssembledDay, into context: ModelContext) {
        let date = Calendar.current.startOfDay(for: assembled.date)
        let existing = (try? context.fetch(FetchDescriptor<PrescriptionRow>())) ?? []
        for row in existing where Calendar.current.isDate(row.date, inSameDayAs: date) {
            context.delete(row)
        }
        for p in prescriptions {
            context.insert(PrescriptionRow(date: date, prescription: p,
                                           state: assembled.readiness.state))
        }
        try? context.save()
    }

    // MARK: - Copy

    static func phrase(for state: ReadinessState) -> String {
        switch state {
        case .aboveBaseline: return "Above baseline"
        case .atBaseline: return "At baseline"
        case .belowBaseline: return "Below baseline"
        case .wellBelowBaseline: return "Well below baseline"
        }
    }

    static func call(for result: ReadinessResult) -> String {
        if let gate = result.gateApplied {
            switch gate {
            case .elevatedWristTemperature:
                return "Your temperature is up. Train light, or not at all."
            case .acuteLoadSpike:
                return "Your load has climbed fast this week. Holding you at baseline."
            }
        }
        switch result.state {
        case .aboveBaseline: return "Add weight if the first set moves fast."
        case .atBaseline: return "Run the program as written."
        case .belowBaseline: return "Pull back a little. Keep the reps honest."
        case .wellBelowBaseline: return "Cut the load. Today is technique, not records."
        }
    }
}
