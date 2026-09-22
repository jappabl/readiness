import CryptoKit
import DeviceCheck
import Foundation

/// Proving this is a real build of this app on a real iPhone.
///
/// The proxy holds provider keys and spends real money on every request, so the one
/// question it has to answer before doing anything is whether the caller is the app. A
/// shared secret cannot answer it: an IPA is a zip, and anything compiled into it is
/// extracted in minutes. App Attest answers it with hardware.
///
/// Two steps, and they are not the same shape. Once per install, a key is generated in
/// the Secure Enclave and *attested*: Apple returns a statement, signed by a certificate
/// chaining to their own root, that says this key belongs to this app on genuine
/// hardware. After that, each request carries an *assertion*: a signature over that
/// request's own contents, with a counter that only goes up.
///
/// Nothing here can run in the simulator, where `DCAppAttestService.isSupported` is
/// false. Debug builds fall back to the development secret, which is why that exists.
enum AppAttest {

    private static let service = DCAppAttestService.shared
    private static let keyIDKey = "attest.keyID"
    private static let attestedKey = "attest.registered"
    private static let memberKey = "member.number"

    /// Which member this install is, issued by the server the first time it registered.
    ///
    /// Anchored to the install, which is the honest place for it: App Attest generates a
    /// fresh key on a reinstall, so a deleted app comes back as a new member. The
    /// founder price does not, because a subscription lives on the Apple account and
    /// survives the same reinstall. Somebody can lose the badge and keep what they paid
    /// for, which is the right way round.
    private(set) static var member: Int? {
        get {
            let stored = UserDefaults.standard.integer(forKey: memberKey)
            return stored > 0 ? stored : nil
        }
        set { UserDefaults.standard.set(newValue ?? 0, forKey: memberKey) }
    }

    static var isSupported: Bool { service.isSupported }

    /// The key id, generated and registered on first use.
    ///
    /// Stored in UserDefaults rather than the Keychain on purpose: it is an opaque
    /// identifier, not a secret, and a Keychain item surviving a delete-and-reinstall
    /// would leave the app holding a key id the Secure Enclave no longer has.
    private static var keyID: String? {
        get { UserDefaults.standard.string(forKey: keyIDKey) }
        set { UserDefaults.standard.set(newValue, forKey: keyIDKey) }
    }

    static var isRegistered: Bool {
        get { UserDefaults.standard.bool(forKey: attestedKey) }
        set { UserDefaults.standard.set(newValue, forKey: attestedKey) }
    }

    /// What every request carries: which key, and this request's signature.
    struct Proof {
        let keyID: String
        /// Base64 assertion over `clientDataHash`.
        let assertion: String
        /// The hash that was signed, so the server can rebuild what it should verify.
        let challenge: String
    }

    enum Failure: Error { case unsupported, notRegistered }

    /// Why the last attempt did not produce a proof, for the diagnostics row in Profile.
    ///
    /// Kept because the failure is otherwise invisible: with the server not yet
    /// requiring attestation, a broken registration looks exactly like a working one
    /// from the outside, right up until the flag is flipped and nothing works.
    private(set) static var lastFailure: String?

    static var status: String {
        if !isSupported { return "Not available on this device" }
        if let lastFailure { return lastFailure }
        return isRegistered ? "Registered" : "Not registered yet"
    }

    /// Registers this install with the server, once.
    ///
    /// The challenge comes from the server so an attestation cannot be replayed: it is
    /// woven into the hash Apple signs, and the server will not accept a statement built
    /// around a challenge it did not just issue.
    static func register(baseURL: URL) async throws {
        guard isSupported else { throw Failure.unsupported }
        if isRegistered, keyID != nil { return }

        let challenge = try await fetchChallenge(baseURL: baseURL)
        let key = try await service.generateKey()
        let hash = Data(SHA256.hash(data: Data(challenge.utf8)))
        let attestation = try await service.attestKey(key, clientDataHash: hash)

        var request = URLRequest(url: baseURL.appendingPathComponent("v1/attest"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "keyId": key,
            "challenge": challenge,
            "attestation": attestation.base64EncodedString(),
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            // Deliberately not stored. An install that failed to register tries again
            // on the next request rather than carrying a key the server never accepted.
            lastFailure = "Server refused registration (\(status)): "
                + (String(data: data, encoding: .utf8) ?? "")
            throw Failure.notRegistered
        }
        keyID = key
        isRegistered = true
        // Issued once, on the registration that created this install. A later
        // registration returns the same number rather than spending another.
        if let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let issued = body["member"] as? Int, issued > 0 {
            member = issued
        }
        lastFailure = nil
    }

    /// Signs one request, or returns nil having recorded why it could not.
    ///
    /// Nil rather than a thrown error on purpose. Every caller wants the same thing from
    /// a failure here, which is to send the request anyway and let the server decide, so
    /// making them all write that is only an opportunity to get it wrong once.
    static func proof(for body: Data, baseURL: URL) async -> Proof? {
        guard isSupported else { return nil }
        do {
            try await register(baseURL: baseURL)
            guard let keyID else { return nil }

            let challenge = try await fetchChallenge(baseURL: baseURL)
            // Challenge and body together: the first stops a replay, the second stops
            // the same signature standing for a different request.
            var signed = Data(challenge.utf8)
            signed.append(body)
            let hash = Data(SHA256.hash(data: signed))
            let assertion = try await service.generateAssertion(keyID, clientDataHash: hash)
            lastFailure = nil
            return Proof(keyID: keyID,
                         assertion: assertion.base64EncodedString(),
                         challenge: challenge)
        } catch {
            // A key the Secure Enclave no longer recognises, or a server that refused
            // it. Either way the next attempt starts over rather than retrying a key
            // that will keep failing.
            if lastFailure == nil { lastFailure = String(describing: error) }
            isRegistered = false
            return nil
        }
    }

    private static func fetchChallenge(baseURL: URL) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/challenge"))
        request.httpMethod = "POST"
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let challenge = object["challenge"] as? String else {
            throw Failure.notRegistered
        }
        return challenge
    }
}
