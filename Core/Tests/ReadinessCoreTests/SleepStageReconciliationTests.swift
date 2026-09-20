import Foundation
import Testing
@testable import ReadinessCore

/// Two devices tracking the same night each union their own samples, and the per-stage
/// totals are then summed, so the staged hours can exceed the night that held them. The
/// engine reconciles by keeping the proportions and fitting them to the night — that is
/// what it scores. What it *published* was the raw hours, so the ring and the stage key
/// drew and printed sleep that did not happen.
@Suite("Reconciling stages across two devices")
struct SleepStageReconciliationTests {

    private let calendar = Calendar(identifier: .gregorian)

    /// A watch and a phone disagreeing about the same seven and a half hours. Each is
    /// internally consistent; together they stage 11.5 hours of a 7.5-hour night.
    private func twoDeviceNight() -> SleepBreakdown {
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 7))!
        let start = end.addingTimeInterval(-7.5 * 3600)
        func slice(_ from: Double, _ to: Double, _ stage: SleepStage) -> SleepInterval {
            SleepInterval(start: start.addingTimeInterval(from * 3600),
                          end: start.addingTimeInterval(to * 3600), stage: stage)
        }
        let watch = [slice(0, 1.5, .deep), slice(1.5, 5.0, .core), slice(5.0, 7.5, .rem)]
        let phone = [slice(0, 3.0, .deep), slice(3.0, 7.5, .core)]
        return SleepAggregator.byWakeDay(watch + phone, calendar: calendar)[
            calendar.startOfDay(for: end)]!
    }

    /// Fourteen ordinary single-device nights, so the stage rows have a distribution to
    /// be measured against and are published at all.
    private func history() -> [SleepBreakdown] {
        (1...14).map { day in
            let end = calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: 7))!
            let start = end.addingTimeInterval(-8 * 3600)
            func slice(_ from: Double, _ to: Double, _ stage: SleepStage) -> SleepInterval {
                SleepInterval(start: start.addingTimeInterval(from * 3600),
                              end: start.addingTimeInterval(to * 3600), stage: stage)
            }
            return SleepAggregator.byWakeDay(
                [slice(0, 1.2, .deep), slice(1.2, 6.0, .core), slice(6.0, 8.0, .rem)],
                calendar: calendar)[calendar.startOfDay(for: end)]!
        }
    }

    private func score(_ breakdown: SleepBreakdown) -> SignalScore {
        SleepScore.of(SleepInput(breakdown: breakdown, durationHours: breakdown.asleepHours,
                                 history: history(), strain: nil, napHours: nil,
                                 sleepingHeartRate: nil, daytimeHeartRate: nil,
                                 calendar: calendar))
    }

    /// The fixture is only interesting if it really over-stages, so that is asserted
    /// rather than assumed.
    @Test("two devices really do stage more than the night held")
    func fixtureOverStages() {
        let night = twoDeviceNight()
        #expect(abs(night.asleepHours - 7.5) < 0.01)
        #expect(night.deepHours + night.remHours + night.coreHours > night.asleepHours * 1.4)
    }

    /// The property the ring needs, and the one that was false: whatever is published for
    /// the stages has to fit inside the night. Drawn against a night of 7.5 hours, raw
    /// hours of deep 3.0 and REM 2.5 leave 2.0 for light — and 1.04 of those deep hours
    /// were a second device's opinion counted twice.
    @Test("published stage hours fit inside the night")
    func stagesFitTheNight() throws {
        let night = twoDeviceNight()
        let result = score(night)
        let deep = try #require(result.contributor("deep")?.value)
        let rem = try #require(result.contributor("rem")?.value)
        #expect(deep + rem <= night.asleepHours + 0.001,
                "deep \(deep) + REM \(rem) exceed a \(night.asleepHours) h night")
    }

    /// And they are the hours the engine actually scored, not the raw ones. `share()`
    /// divides by `max(asleep, deep + rem + core)`, so this is that same denominator.
    @Test("published stage hours are the ones that were scored")
    func stagesMatchWhatWasScored() throws {
        let night = twoDeviceNight()
        let result = score(night)
        let total = max(night.asleepHours, night.deepHours + night.remHours + night.coreHours)
        let scale = night.asleepHours / total
        let deep = try #require(result.contributor("deep")?.value)
        let rem = try #require(result.contributor("rem")?.value)
        #expect(abs(deep - night.deepHours * scale) < 0.001)
        #expect(abs(rem - night.remHours * scale) < 0.001)
        #expect(deep < night.deepHours, "nothing was reconciled at all")
    }

    /// A night one device staged is untouched, which is every night for most people.
    @Test("a single-device night is published exactly as recorded")
    func singleDeviceUnchanged() throws {
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 10, hour: 7))!
        let start = end.addingTimeInterval(-8 * 3600)
        func slice(_ from: Double, _ to: Double, _ stage: SleepStage) -> SleepInterval {
            SleepInterval(start: start.addingTimeInterval(from * 3600),
                          end: start.addingTimeInterval(to * 3600), stage: stage)
        }
        let night = SleepAggregator.byWakeDay(
            [slice(0, 1.2, .deep), slice(1.2, 6.0, .core), slice(6.0, 8.0, .rem)],
            calendar: calendar)[calendar.startOfDay(for: end)]!
        let result = score(night)
        #expect(abs(try #require(result.contributor("deep")?.value) - night.deepHours) < 0.001)
        #expect(abs(try #require(result.contributor("rem")?.value) - night.remHours) < 0.001)
    }
}
