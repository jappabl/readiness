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

    /// Fixed, so scheduling again replaces the pending one rather than stacking a
    /// second warning about the same charge.
    private static let trialReminderID = "trial.ending"
    /// Fixed for the same reason: every refresh rebooks tonight's, replacing it.
    private static let bedtimeTargetID = "bedtime.target"
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
        // Everything Jett had queued up, and nothing about money. Somebody who has asked
        // the coach to be quiet has not asked to be charged without warning, and the
        // trial reminder is the one message here they cannot get anywhere else in time.
        Task { [center] in
            let pending = await center.pendingNotificationRequests()
            center.removePendingNotificationRequests(withIdentifiers:
                pending.map(\.identifier).filter { $0 != Self.trialReminderID })
        }
    }

    /// The only notification this app sends about money.
    ///
    /// Deliberately not gated on `isEnabled`. That switch is for the coach; this is a
    /// warning that a card is about to be charged, and the two are not the same
    /// question. It does still need the system permission, because nothing can be sent
    /// without it.
    ///
    /// Pass nil to withdraw it: the trial ended, or renewal was turned off, or the
    /// subscription went away.
    func updateTrialReminder(_ charge: Subscriptions.TrialCharge?, now: Date = .now) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.trialReminderID])
        guard let charge, systemStatus == .authorized else { return }
        guard let fire = TrialReminder.fireDate(trialEnds: charge.ends, now: now) else { return }

        let content = UNMutableNotificationContent()
        content.body = TrialReminder.body(priceLine: charge.priceLine)
        content.sound = .default
        // Not threaded with the coach on purpose. This is the one message that should
        // not collapse into a stack of Jett saying things about sleep.
        let request = UNNotificationRequest(
            identifier: Self.trialReminderID, content: content,
            trigger: UNTimeIntervalNotificationTrigger(
                timeInterval: fire.timeIntervalSince(now), repeats: false))
        try? await center.add(request)
    }

    /// Asks the engine, and posts whatever it returns.
    ///
    /// The record is written only after the notification is accepted. Persisting it any
    /// earlier would burn the day and the coin for a message nobody saw, which the
    /// engine's own documentation warns about.
    func considerSpeaking(_ input: NotificationDecision.Input,
                          trigger: SpeakingWindow.Trigger = .appClosed) async {
        guard isEnabled, systemStatus == .authorized else { return }
        // Before the speaking window, because booking is not speaking: whatever woke
        // the app, the message itself goes out an hour before bed. Then the decision
        // below knows about it, so the same night is never announced twice.
        await bookBedtime(input)
        let input = input.with(record: record)
        guard SpeakingWindow.allows(trigger, at: input.now) else { return }
        guard let outcome = NotificationDecision.next(input) else { return }

        let content = UNMutableNotificationContent()
        content.body = outcome.body
        content.sound = .default
        // Threaded so several days of these collapse in Notification Centre rather than
        // stacking into a column of Jett.
        content.threadIdentifier = "coach-jett"

        // A watch hands over a finished night the moment it ends, which can be minutes
        // before somebody has their eyes properly open. Twelve minutes is the difference
        // between arriving with their morning and arriving in the middle of it.
        let delay = SpeakingWindow.delay(after: trigger)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content,
            trigger: delay > 0 ? UNTimeIntervalNotificationTrigger(timeInterval: delay,
                                                                   repeats: false) : nil)
        do {
            try await center.add(request)
            save(outcome.record)
        } catch {
            // Nothing was shown, so nothing is spent. The same decision can be made
            // again on the next refresh.
        }
    }

    /// Books, rebooks or withdraws tonight's bedtime target.
    private func bookBedtime(_ input: NotificationDecision.Input) async {
        switch NotificationDecision.bedtimeBooking(input) {
        case .leave:
            return
        case .withdraw:
            center.removePendingNotificationRequests(withIdentifiers: [Self.bedtimeTargetID])
        case .book(let plan):
            let wait = plan.fireAt.timeIntervalSinceNow
            guard wait > 0 else { return }
            let content = UNMutableNotificationContent()
            content.body = plan.body
            content.sound = .default
            content.threadIdentifier = "coach-jett"
            let request = UNNotificationRequest(
                identifier: Self.bedtimeTargetID, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false))
            do {
                try await center.add(request)
                save(plan.record)
            } catch {
                // Not booked, so not recorded: the next refresh tries again.
            }
        }
    }

    private func save(_ newRecord: NotificationRecord) {
        record = newRecord
        if let data = try? JSONEncoder().encode(newRecord) {
            UserDefaults.standard.set(data, forKey: Self.recordKey)
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
