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

    public static func of(_ values: [Double]) -> BaselineSummary? {
        let usable = values.filter(\.isFinite)
        guard usable.count >= minimumReadings else { return nil }

        let mean = usable.reduce(0, +) / Double(usable.count)
        let variance = usable.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(usable.count)
        var deviation = variance.squareRoot()

        // A band of zero width contains exactly one value, which is useless to draw and
        // reads as a claim of impossible precision. Give a flat history a hair of room.
        if deviation <= 0 { deviation = max(abs(mean) * 0.01, 0.5) }

        return BaselineSummary(mean: mean, deviation: deviation, count: usable.count)
    }
}
