import Foundation

/// One line saying what a chart means.
///
/// A line on its own is a shape. Three of them stacked is three shapes. This is the
/// sentence that turns each one into a reason, and it is derived from the data rather
/// than written by the model, so it cannot claim something the numbers do not show.
///
/// It prefers "lowest in 28 days" over "well below baseline" when both are true,
/// because being at the edge of your own range is the more useful fact and the one a
/// person can check against the picture in front of them.
public enum MetricNarration {

    /// What a metric sitting on its own baseline is called.
    ///
    /// Was "Sitting where it usually does", which is eleven syllables to say nothing
    /// happened. Exposed as a constant so callers can recognise the null result and
    /// decline to print it, which is usually the right move: a dot resting on the
    /// baseline tick has already said this.
    public static let unremarkable = "Normal for you"

    /// Below this, a reading is close enough to baseline to call it usual.
    static let usualBand = 0.6
    /// Fewer points than this and an extreme means nothing.
    static let minimumWindow = 5

    public static func brief(reading: MetricReading, series: [Double],
                             spanDays: Int? = nil) -> String {
        brief(value: reading.value, zScore: reading.zScore, series: series,
              spanDays: spanDays)
    }

    /// The same sentence for a quantity that is not one of the scored metrics. Nothing
    /// here ever depended on the kind — only on where the value sits in its own history —
    /// and requiring a `MetricKind` meant sleep duration could not be described at all.
    /// `spanDays` is how many calendar days the series covers, when that is not simply
    /// its length. A chart's points are its *recordings*, so counting them and calling the
    /// answer days told a four-nights-a-week wearer "Lowest in 16 days" about a window
    /// twenty-eight days wide.
    public static func brief(value: Double, zScore: Double, series: [Double],
                             spanDays: Int? = nil) -> String {
        if let extreme = extremeNote(value: value, zScore: zScore, series: series,
                                     spanDays: spanDays) {
            return extreme
        }
        guard abs(zScore) >= usualBand else { return unremarkable }
        return Self.capitalised(deviation(zScore))
    }

    private static func extremeNote(value: Double, zScore: Double, series: [Double],
                                    spanDays: Int? = nil) -> String? {
        guard series.count >= minimumWindow,
              abs(zScore) >= usualBand,
              let low = series.min(), let high = series.max(),
              high > low else { return nil }

        // Compared against the drawn window, so the words match the picture.
        let tolerance = (high - low) * 0.02
        let days = spanDays ?? series.count
        if value <= low + tolerance { return "Lowest in \(days) days" }
        if value >= high - tolerance { return "Highest in \(days) days" }
        return nil
    }

    /// Mirrors the phrasing used on the evidence screen, so one number is not described
    /// two different ways in two places.
    private static func deviation(_ z: Double) -> String {
        let direction = z < 0 ? "below" : "above"
        switch abs(z) {
        case 2...:  return "well \(direction) baseline"
        case 1..<2: return "\(direction) baseline"
        default:    return "slightly \(direction) baseline"
        }
    }

    private static func capitalised(_ text: String) -> String {
        text.prefix(1).uppercased() + text.dropFirst()
    }
}
