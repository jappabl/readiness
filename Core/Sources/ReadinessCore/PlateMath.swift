import Foundation

public enum PlateMath {
    /// Round a computed load to something that can actually be loaded on a bar.
    /// A non-positive increment is treated as "no rounding" rather than a divide by zero.
    public static func round(_ weight: Double, toIncrement increment: Double) -> Double {
        guard increment > 0 else { return Swift.max(0, weight) }
        return Swift.max(0, (weight / increment).rounded() * increment)
    }
}
