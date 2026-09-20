import Foundation

/// The occasions on which Coach Jett initiates a message.
///
/// Gym arrival is deliberately absent. It is transactional rather than editorial: it
/// responds to something the user just did, the way a delivery notification does. And
/// it is decided by CoreLocation in the app layer, so it never reaches this engine and
/// never competes for the allowance the initiated messages share.
///
/// See docs/superpowers/specs/2026-09-19-notifications-design.md.
public enum NotificationMoment: String, Sendable, Codable, Equatable, CaseIterable {
    case morningVerdict
    case illnessGate
    case newInsight
    case bedtimeTarget

    /// Whether this moment draws from the speaking budget.
    ///
    /// The morning verdict does not. Budgeting it would treat "how did I sleep" as one
    /// nice-to-have among several, when it is the thing the user opened an account for.
    /// And it would silence the fifth consecutive rough night, which is a fifth day they
    /// should train differently.
    public var spendsBudget: Bool {
        switch self {
        case .morningVerdict, .illnessGate: return false
        case .newInsight, .bedtimeTarget: return true
        }
    }
}
