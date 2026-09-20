import Foundation

/// The middle of somebody's readings and how far they usually stray from it.
///
/// Exists so a picture can show a normal rather than a line. A raw series is a shape;
/// a middle with a band around it is a claim you can check by eye, which is what the
/// reveal at the end of onboarding is actually asserting.
public struct BaselineSummary: Equatable, Sendable {

    /// Fewer readings than this and there is no normal worth drawing. Saying nothing is
    /// better than drawing a confident band through five points.
    public static let minimumReadings = 7

    public let mean: Double
    public let deviation: Double
    public let count: Int

    public var low: Double { mean - deviation }
    public var high: Double { mean + deviation }

    public func contains(_ value: Double) -> Bool {
        value.isFinite && value >= low && value <= high
    }

    /// `minimumDeviation` sets the narrowest band this quantity can have.
    ///
    /// The default floor of half a unit suits the streams this was written for — a
    /// resting heart rate, an HRV in milliseconds. It is nonsense for a quantity that
    /// lives between zero and one: a deep-sleep share of 0.15 against a floor of 0.5
    /// makes every night exactly average, forever. Anything scored on a fraction has to
    /// pass its own floor.
    public static func of(_ values: [Double], minimumDeviation: Double? = nil) -> BaselineSummary? {
        let usable = values.filter(\.isFinite)
        guard usable.count >= minimumReadings else { return nil }

        let mean = usable.reduce(0, +) / Double(usable.count)
        let variance = usable.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(usable.count)
        var deviation = variance.squareRoot()

        // A band of zero width contains exactly one value, which is useless to draw and
        // reads as a claim of impossible precision. Give a flat history a hair of room.
        // An explicit floor is a property of the quantity and always applies: a history
        // with almost no spread would otherwise turn a small move into a z-score of a
        // thousand. Without one, only a perfectly flat history is widened, which is the
        // behaviour the streams this was built for already depend on.
        if let minimumDeviation {
            deviation = Swift.max(deviation, minimumDeviation)
        } else if deviation <= 0 {
            deviation = Swift.max(abs(mean) * 0.01, 0.5)
        }

        return BaselineSummary(mean: mean, deviation: deviation, count: usable.count)
    }
}
