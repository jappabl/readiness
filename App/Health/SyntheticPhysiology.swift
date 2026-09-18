import Foundation

/// Generates plausible, internally-correlated overnight physiology.
///
/// This exists so the app can be built and inspected on a simulator, whose HealthKit
/// store is real but empty. It is deterministic: the same seed gives the same history,
/// so a screenshot of a given state is reproducible.
///
/// It proves the app works. It cannot answer whether readiness predicts performance —
/// only real data can do that.
struct SyntheticPhysiology {

    /// A small deterministic PRNG. Foundation's random sources are not reproducible
    /// across runs, and reproducibility is the whole point here.
    private struct Generator: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    private var rng: Generator

    init(seed: UInt64 = 20260917) { rng = Generator(seed: seed) }

    private mutating func gaussian(_ mean: Double, _ sd: Double) -> Double {
        let u1 = Double.random(in: 0.0001...0.9999, using: &rng)
        let u2 = Double.random(in: 0.0001...0.9999, using: &rng)
        let z = (-2 * Foundation.log(u1)).squareRoot() * Foundation.cos(2 * .pi * u2)
        return mean + z * sd
    }

    /// `days` days ending today, oldest first.
    mutating func series(days: Int, endingOn endDate: Date = Date(),
                         calendar: Calendar = .current) -> [DailyPhysiology] {
        var out: [DailyPhysiology] = []
        // A slow-moving latent "how recovered am I" factor. AR(1) so runs of good and
        // bad days cluster the way real life does, instead of flickering day to day.
        var latent = 0.0
        var illnessDaysRemaining = 0

        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let date = calendar.date(byAdding: .day, value: -offset,
                                           to: calendar.startOfDay(for: endDate)) else { continue }

            latent = 0.75 * latent + gaussian(0, 0.62)

            // Training weeks have a shape: heavier midweek, easier on the weekend.
            let weekday = calendar.component(.weekday, from: date)
            let weekly = (weekday == 1 || weekday == 7) ? 0.30 : -0.12

            // Occasional illness episodes, which is what the temperature gate is for.
            if illnessDaysRemaining > 0 {
                illnessDaysRemaining -= 1
            } else if Double.random(in: 0...1, using: &rng) < 0.012 {
                illnessDaysRemaining = Int.random(in: 2...4, using: &rng)
            }
            let ill = illnessDaysRemaining > 0
            let illnessHit = ill ? -1.35 : 0.0

            let f = latent + weekly + illnessHit

            out.append(DailyPhysiology(
                date: date,
                hrvSDNN: max(8, gaussian(54 + 11.5 * f, 3.4)),
                restingHeartRate: max(35, gaussian(53 - 3.9 * f + (ill ? 4.5 : 0), 1.7)),
                sleepHours: min(11, max(3.0, gaussian(7.35 + 0.72 * f, 0.42))),
                respiratoryRate: max(9, gaussian(14.6 - 0.58 * f + (ill ? 0.9 : 0), 0.4)),
                bloodOxygenPercent: min(100, max(90, gaussian(97.4 + 0.42 * f, 0.5))),
                // Absolute sleeping wrist temperature; the deviation is derived later
                // against the user's own rolling baseline, as HealthKit does not store one.
                wristTemperatureC: ill
                    ? gaussian(33.50 + 0.78, 0.16)
                    : gaussian(33.50, 0.14)
            ))
        }
        return out
    }
}

/// Serves synthetic data directly, without touching HealthKit. Used only when the
/// HealthKit store is empty and the app is running on a simulator.
struct SyntheticHealthSource: HealthSource {
    let seed: UInt64

    func requestAuthorization() async throws {}

    func dailySeries(days: Int) async throws -> [DailyPhysiology] {
        var generator = SyntheticPhysiology(seed: seed)
        return generator.series(days: days)
    }
}
