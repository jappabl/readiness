import Testing
import Foundation
import CryptoKit
@testable import ReadinessCore

/// The same inputs and fingerprints are pinned in the server's tests
/// (server/test/assertion.test.ts), so the app and the Worker cannot quietly disagree
/// about what a signature covers.
@Suite("What a request's signature covers")
struct AssertionMessageTests {
    let challenge = "1700000000000.3f2c9a1e-0000-4000-8000-000000000000.c2lnbmF0dXJl"
    let body = Data(#"{"messages":[]}"#.utf8)
    let purchase = "eyJhbGciOiJFUzI1NiJ9.eyJ0cmFuc2FjdGlvbklkIjoiMSJ9.c2ln"

    func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test("without a purchase, the challenge and then the body, as before")
    func withoutPurchase() {
        let message = AssertionMessage.bytes(challenge: challenge, body: body, purchase: nil)
        #expect(digest(message) == "6660619ef472a1f49abdf3767d9beafd6f2f5e2ad70f4c13d14456fdb542a9d5")
    }

    @Test("with a purchase, its fingerprint as well")
    func withPurchase() {
        let message = AssertionMessage.bytes(challenge: challenge, body: body, purchase: purchase)
        #expect(message.count == challenge.utf8.count + body.count + 32)
        #expect(digest(message) == "1491dc1161f5adcd2f7fe4a2bb0f2174ef1e02e11467097b11fd415a4877f16a")
    }

    @Test("an empty purchase counts as none")
    func emptyIsNone() {
        #expect(AssertionMessage.bytes(challenge: challenge, body: body, purchase: "")
                == AssertionMessage.bytes(challenge: challenge, body: body, purchase: nil))
    }
}
