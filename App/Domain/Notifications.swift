import Foundation
import UserNotifications

/// Delivering what `NotificationDecision` decided.
///
/// Every rule about whether to speak, which moment wins, and what the words are lives in
/// Core and is settled by `swift test`. Nothing here decides anything: it gathers the
/// inputs, asks, and posts. That split is the reason the engine could be built and
/// proven before any of this existed.
@MainActor
@Observable
final class Notifications {

    /// Whether the user has asked for these at all. Separate from the system permission:
    /// somebody can allow notifications and still want Jett quiet.
    var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    private(set) var systemStatus: UNAuthorizationStatus = .notDetermined
    private(set) var record: NotificationRecord

    /// Without a delegate, iOS drops a notification posted while the app is in front:
    /// it neither banners nor waits on the lock screen, it is simply gone. These are
    /// written for somebody who is not looking at the app, so the decision runs when it
    /// leaves the foreground, and this is the belt to that braces.
    private let foreground = ForegroundPresenter()

    private static let enabledKey = "notifications.enabled"
    private static let recordKey = "notifications.record"
    private let center = UNUserNotificationCenter.current()

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        // A record that cannot be decoded starts again rather than wedging notifications
        // forever, which is what the type's own documentation asks the app to do.
        record = (UserDefaults.standard.data(forKey: Self.recordKey))
            .flatMap { try? JSONDecoder().decode(NotificationRecord.self, from: $0) }
            ?? NotificationRecord()
        center.delegate = foreground
    }

    func refreshStatus() async {
        systemStatus = await center.notificationSettings().authorizationStatus
    }

    /// Returns whether Jett may now speak. False covers both a refusal and a user who
    /// turned the switch off again.
    @discardableResult
    func enable() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshStatus()
        isEnabled = granted
        return granted
    }

    func disable() {
        isEnabled = false
        center.removeAllPendingNotificationRequests()
    }

    /// Asks the engine, and posts whatever it returns.
    ///
    /// The record is written only after the notification is accepted. Persisting it any
    /// earlier would burn the day and the coin for a message nobody saw, which the
    /// engine's own documentation warns about.
    func considerSpeaking(_ input: NotificationDecision.Input) async {
        guard isEnabled, systemStatus == .authorized else { return }
        guard let outcome = NotificationDecision.next(input) else { return }

        let content = UNMutableNotificationContent()
        content.body = outcome.body
        content.sound = .default
        // Threaded so several days of these collapse in Notification Centre rather than
        // stacking into a column of Jett.
        content.threadIdentifier = "coach-jett"

        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        do {
            try await center.add(request)
            record = outcome.record
            if let data = try? JSONEncoder().encode(record) {
                UserDefaults.standard.set(data, forKey: Self.recordKey)
            }
        } catch {
            // Nothing was shown, so nothing is spent. The same decision can be made
            // again on the next refresh.
        }
    }
}


/// Shows a notification that arrives while the app is open, rather than letting the
/// system discard it. Only ever reached when the decision and the return to the app race
/// each other, which the scene phase makes rare rather than impossible.
private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
