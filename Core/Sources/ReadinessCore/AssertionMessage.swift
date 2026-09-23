import Foundation
import CryptoKit

/// Exactly what a request's App Attest signature covers.
///
/// The challenge, so a signature cannot be replayed. The body, so it cannot stand for a
/// different question. And, when the request carries a purchase, that purchase's
/// fingerprint, because a header nobody signed can be swapped by anybody who can watch
/// their own phone's traffic, and one subscriber's proof would be everybody's Pro.
///
/// No purchase leaves the message exactly as it was before purchases were signed, so a
/// build that has never bought anything keeps working against a server that checks.
///
/// Pinned byte for byte against the server's `assertionMessage` by a shared test vector.
public enum AssertionMessage {
    public static func bytes(challenge: String, body: Data, purchase: String?) -> Data {
        var message = Data(challenge.utf8)
        message.append(body)
        if let purchase, !purchase.isEmpty {
            message.append(contentsOf: SHA256.hash(data: Data(purchase.utf8)))
        }
        return message
    }
}
