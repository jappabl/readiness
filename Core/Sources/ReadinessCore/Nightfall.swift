import Foundation

/// Which scheme the app wears, by the clock rather than by the system setting.
///
/// The app is light. A coach rendered in near-black with saturated accents reads as a
/// dashboard for people who enjoy dashboards, and this one is meant to read as a person
/// who knows what you did last night.
///
/// It goes dark anyway between these hours, because the first thing somebody does with
/// a recovery app is open it in a dark bedroom before they are properly awake, and a
/// full-brightness white screen at that moment is the single most resented thing a
/// health app can do.
///
/// Both hours are constants so the window is easy to move, and easy to delete if
/// following the system turns out to be the better manners after all.
public enum Nightfall {

    public static let darkFromHour = 21
    public static let lightFromHour = 6

    public static func isNight(at date: Date, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        // The window wraps midnight, so it is two ranges rather than one.
        return hour >= darkFromHour || hour < lightFromHour
    }

    /// The next moment the answer changes, so a session left open overnight does not
    /// sit in yesterday's scheme until somebody relaunches.
    public static func nextChange(after date: Date, calendar: Calendar = .current) -> Date? {
        let targetHour = isNight(at: date, calendar: calendar) ? lightFromHour : darkFromHour
        return calendar.nextDate(after: date,
                                 matching: DateComponents(hour: targetHour, minute: 0, second: 0),
                                 matchingPolicy: .nextTime)
    }
}

/// What the person asked for, if they asked.
///
/// iOS never reports "no preference": the system is always light or dark, and an app
/// cannot tell a deliberate choice from the default, or see that Automatic is on. So
/// the preference has to be ours. Automatic is the default, and anybody who actually
/// cares sets it once in Profile and is never surprised again.
public enum AppearancePreference: String, CaseIterable, Sendable, Codable {
    case automatic, light, dark

    public var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    public var detail: String? {
        self == .automatic ? "Light by day, dark at night" : nil
    }

    /// Nil means follow the clock.
    public func wantsDark(at date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .light: return false
        case .dark: return true
        case .automatic: return Nightfall.isNight(at: date, calendar: calendar)
        }
    }
}
