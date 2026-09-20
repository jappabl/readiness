#if DEBUG
import Foundation

/// A plausible sixty days of physiology, for looking at the whole app at once.
///
/// Deliberately not random: the same series every launch, so a screenshot taken today
/// can be compared with one taken next week. Deliberately not flat either — every
/// engine in the app measures today against a spread, and a series with no spread makes
/// all three scores say the same thing.
enum DemoPhysiology {

    static let profile: HealthProfile = {
        var components = DateComponents()
        components.year = 1997
        components.month = 4
        components.day = 12
        return HealthProfile(heightCM: 178, dateOfBirth: components,
                             biologicalSex: HealthProfile.BiologicalSex.male)
    }()

    /// Oldest first, ending today, the way `DayAssembler` expects it.
    static func series(days: Int = 60, on today: Date = Date()) -> [DailyPhysiology] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: today)
        var random = SplitMix64(seed: 20260919)

        return (0..<days).reversed().compactMap { back -> DailyPhysiology? in
            guard let date = calendar.date(byAdding: .day, value: -back, to: start) else { return nil }
            let isToday = back == 0
            // Today is a middling morning: HRV a little down, resting rate a little up.
            // Enough to have something to say without being alarming.
            let drift = random.nextGaussian()
            let hrv = 58 + drift * 6 - (isToday ? 4 : 0)
            let rhr = 53 + drift * -1.5 + (isToday ? 1 : 0)
            let sleepHours = max(4.5, 7.6 + random.nextGaussian() * 0.7 - (isToday ? 0.5 : 0))
            let awake = max(0, 0.3 + random.nextGaussian() * 0.15)

            var night = SleepBreakdown()
            night.asleepHours = sleepHours
            night.deepHours = sleepHours * (0.16 + random.nextGaussian() * 0.02)
            night.remHours = sleepHours * (0.22 + random.nextGaussian() * 0.03)
            night.coreHours = sleepHours - night.deepHours - night.remHours
            night.awakeHours = awake
            night.inBedHours = sleepHours + awake
            night.recordedContinuity = sleepHours / (sleepHours + awake)
            let wake = calendar.date(bySettingHour: 7, minute: 10, second: 0, of: date) ?? date
            night.primarySleepEnd = wake
            night.primarySleepStart = wake.addingTimeInterval(-(sleepHours + awake) * 3600)

            return DailyPhysiology(
                date: date,
                hrvSDNN: hrv,
                restingHeartRate: rhr,
                sleepHours: sleepHours,
                respiratoryRate: 14.2 + random.nextGaussian() * 0.4,
                bloodOxygenPercent: 97.1 + random.nextGaussian() * 0.5,
                wristTemperatureC: 33.4 + random.nextGaussian() * 0.15,
                sleep: night,
                heartRateAverage: 74 + random.nextGaussian() * 4,
                heartRateMin: rhr - 3,
                heartRateMax: 148 + random.nextGaussian() * 20,
                steps: max(1200, 8400 + random.nextGaussian() * 2600),
                activeEnergyKcal: max(150, 520 + random.nextGaussian() * 180),
                basalEnergyKcal: 1680,
                exerciseMinutes: max(0, 38 + random.nextGaussian() * 18),
                standMinutes: 620,
                distanceKm: max(1, 6.2 + random.nextGaussian() * 2),
                bodyMassKg: 74.8 - Double(60 - back) * 0.012,
                bodyFatPercent: 16.4,
                dietaryEnergyKcal: max(1200, 2380 + random.nextGaussian() * 320),
                proteinGrams: max(60, 148 + random.nextGaussian() * 22),
                carbohydrateGrams: max(80, 246 + random.nextGaussian() * 40),
                fatGrams: max(30, 78 + random.nextGaussian() * 14),
                waterLiters: 2.1,
                heartRateSamples: samples(for: date, calendar: calendar, random: &random),
                sleepingHeartRate: rhr + 1,
                wakingHeartRate: 72 + random.nextGaussian() * 3,
                workoutCount: back % 2 == 0 ? 1 : 0,
                workoutMinutes: back % 2 == 0 ? 52 : 0,
                workoutEnergyKcal: back % 2 == 0 ? 410 : 0)
        }
    }

    /// A day in five-minute buckets: asleep, about the place, a session in the evening.
    private static func samples(for date: Date, calendar: Calendar,
                                random: inout SplitMix64) -> [HeartRateSample] {
        let midnight = calendar.startOfDay(for: date)
        var out: [HeartRateSample] = []
        func block(from minute: Int, count: Int, bpm: Double, jitter: Double = 3) {
            for step in 0..<count {
                out.append(HeartRateSample(
                    start: midnight.addingTimeInterval(Double(minute + step * 5) * 60),
                    minutes: 5,
                    beatsPerMinute: bpm + random.nextGaussian() * jitter))
            }
        }
        block(from: 0, count: 86, bpm: 51)        // asleep until just after seven
        block(from: 430, count: 118, bpm: 76)     // the day
        block(from: 1020, count: 5, bpm: 122)     // warm-up
        block(from: 1045, count: 7, bpm: 161, jitter: 6)   // the session
        block(from: 1080, count: 3, bpm: 103)     // cool-down
        block(from: 1095, count: 63, bpm: 70)     // evening
        return out
    }
}

/// Small, fast, and identical on every run, which is the whole point.
private struct SplitMix64 {
    var seed: UInt64
    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var z = seed
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func nextUnit() -> Double { Double(next() >> 11) * (1.0 / 9007199254740992.0) }
    /// Box-Muller, so the series has a believable spread rather than a flat one.
    mutating func nextGaussian() -> Double {
        let u1 = Swift.max(nextUnit(), 1e-12), u2 = nextUnit()
        return (-2 * Foundation.log(u1)).squareRoot() * Foundation.cos(2 * .pi * u2)
    }
}
#endif
