import Contacts
import ContactsUI
import MessageUI
import SwiftUI
import UIKit

/// Text Hao: one tap to a message addressed to the person who built the app.
///
/// Presented from UIKit rather than as a SwiftUI sheet, so every entry point (Profile,
/// an error line) opens it over whatever is on screen, including sheets, without each
/// of them owning a binding.
@MainActor
enum TextHao {

    private static let delegate = ComposeDelegate()

    /// The words in Jett's messages that open this, and the link they carry. Never leaves
    /// the app: the view that draws the words handles it itself.
    static let inlinePhrase = "text Hao"
    static let link = URL(string: "coachjett://text-hao")!

    /// Whether the save-his-number card has been offered. Once is helpful; twice is a nag.
    private static let contactOfferedKey = "texthao.contact.offered"

    /// Opens Messages to Hao, with a picture of the screen they were on.
    ///
    /// The picture is taken here, before Messages covers the screen.
    static func open(screen: String? = nil, problem: String? = nil) {
        Haptics.light()
        let body = FeedbackMessage.body(context(screen: screen, problem: problem))
        guard MFMessageComposeViewController.canSendText(), let top = topController() else {
            // No Messages here (an iPad without a phone, or Messages switched off). The
            // sms link still reaches him, just without the picture.
            openLink(body)
            return
        }
        let composer = MFMessageComposeViewController()
        composer.recipients = [FeedbackMessage.recipient]
        composer.body = body
        if let png = snapshot()?.pngData() {
            composer.addAttachmentData(png, typeIdentifier: "public.png", filename: "Coach Jett.png")
        }
        composer.messageComposeDelegate = delegate
        top.present(composer, animated: true)
    }

    /// What is on screen right now.
    private static func snapshot() -> UIImage? {
        guard let window = appWindow() else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        return renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
    }

    private static func context(screen: String?, problem: String?) -> FeedbackMessage.Context {
        let info = Bundle.main.infoDictionary
        var system = utsname()
        uname(&system)
        let model = withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return FeedbackMessage.Context(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "?",
            build: info?["CFBundleVersion"] as? String ?? "?",
            systemVersion: UIDevice.current.systemVersion,
            deviceModel: model, screen: screen, problem: problem)
    }

    private static func openLink(_ body: String) {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))
        let text = body.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        guard let url = URL(string: "sms:\(FeedbackMessage.recipient)&body=\(text)") else { return }
        UIApplication.shared.open(url)
    }

    private static func appWindow() -> UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    private static func topController() -> UIViewController? {
        var top = appWindow()?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    /// Hao replies from a number nobody has saved, and with Filter Unknown Senders on,
    /// that reply goes to a list people rarely open. So after the first message actually
    /// sent, iOS's own card offers to save him, with the reason on it. Declining is one
    /// tap, and it is never offered again.
    private static func offerContact() {
        guard !UserDefaults.standard.bool(forKey: contactOfferedKey), let top = topController()
        else { return }
        UserDefaults.standard.set(true, forKey: contactOfferedKey)
        let contact = CNMutableContact()
        contact.givenName = "Hao"
        contact.organizationName = "Coach Jett"
        contact.phoneNumbers = [CNLabeledValue(label: "Coach Jett",
                                               value: CNPhoneNumber(stringValue: FeedbackMessage.recipient))]
        let card = CNContactViewController(forUnknownContact: contact)
        card.contactStore = CNContactStore()
        card.allowsActions = false
        card.message = "Save Hao so his reply doesn't land in Unknown Senders."
        card.navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .done, primaryAction: UIAction { [weak card] _ in card?.dismiss(animated: true) })
        top.present(UINavigationController(rootViewController: card), animated: true)
    }

    private final class ComposeDelegate: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true) {
                guard result == .sent else { return }
                MainActor.assumeIsolated { TextHao.offerContact() }
            }
        }
    }
}

/// The small "Text Hao" under an error, carrying the error with it.
struct TextHaoLink: View {
    let screen: String
    let problem: String?

    var body: some View {
        Button { TextHao.open(screen: screen, problem: problem) } label: {
            Text("Text Hao")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.accent)
        }
        .buttonStyle(.plain)
    }
}
