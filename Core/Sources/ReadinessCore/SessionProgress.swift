import Foundation

/// Where a half-finished session left off.
///
/// The live screen started at the first exercise every time it opened. Inside one
/// sitting that is right, because it advances as you go; reopening a session you had
/// walked away from put you back at the top of the list, on an exercise you had already
/// finished, asking for set four of three. A tester logged three sets of leg press,
/// moved on, closed the app, came back and was handed leg press again.
public enum SessionProgress {

    /// The first exercise still short of what was planned for it.
    ///
    /// Not the count of logged sets and not the furthest one touched: somebody who
    /// skipped an exercise and came back should land on the one they skipped, because
    /// that is the one still owed. When everything is done it is the last exercise, so
    /// reopening a finished session shows the end of it rather than the beginning.
    ///
    /// `planned` and `logged` are parallel, one entry per exercise in order.
    public static func resumeIndex(planned: [Int], logged: [Int]) -> Int {
        guard !planned.isEmpty else { return 0 }
        for index in planned.indices where (logged.indices.contains(index) ? logged[index] : 0) < planned[index] {
            return index
        }
        return planned.count - 1
    }
}
