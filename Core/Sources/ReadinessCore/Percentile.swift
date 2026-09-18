import Foundation

/// Turns a z-score into "where does today sit among my own days".
///
/// A ring needs a number. This one is a real quantity — the share of this user's own
/// days that today beats — rather than an invented 0-100 score. A composite of 0 is the
/// 50th percentile by construction, which is what "at baseline" should mean.
public enum Percentile {

    /// Standard normal CDF, as a 0...1 share.
    public static func fromZ(_ z: Double) -> Double {
        guard z.isFinite else { return z > 0 ? 1 : 0 }
        return 0.5 * (1 + erf(z / 2.0.squareRoot()))
    }

    /// The same value as a whole percent, which is what the ring displays.
    public static func percent(fromZ z: Double) -> Int {
        Int((fromZ(z) * 100).rounded())
    }
}
