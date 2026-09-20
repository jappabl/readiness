import Foundation
import StoreKit

/// The signed proof that this install is entitled.
///
/// StoreKit hands back a JWS that Apple signed. Sending that, rather than a boolean the
/// app computed, is what lets the server decide entitlement without trusting the client
/// and without anybody building accounts.
enum Entitlement {

    /// Cached because `currentEntitlements` is async and every coach request needs this
    /// synchronously while building headers. Refreshed whenever entitlement changes.
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: String?

    static var signedTransaction: String? {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    static func refresh() async {
        var found: String?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  Subscriptions.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            found = result.jwsRepresentation
            break
        }
        lock.lock()
        cached = found
        lock.unlock()
    }
}
