import Foundation

/// Where model requests go.
///
/// One switch, read in two places. With a proxy URL configured the app sends context and
/// turns to our own server, which holds the provider keys, meters the call and composes
/// the request. With no URL it keeps the old direct path, which is what development uses
/// until the server holds real keys, so this can land without stopping anyone working.
///
/// The direct path is not a fallback. It is a development mode, and it goes away with
/// `Keychain.apiKey` and `MealPhotoKey` once the proxy is live. A client that silently
/// falls back to calling a provider with an on-device key would defeat the whole point.
enum Backend {

    /// Set `JettProxyURL` in Info.plist to route through the proxy. Debug builds can
    /// override it with an environment variable, so a local worker can be pointed at
    /// without editing the bundle.
    static var baseURL: URL? {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["JETT_PROXY_URL"],
           !override.isEmpty, let url = URL(string: override) { return url }
        #endif
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "JettProxyURL") as? String,
              !raw.trimmingCharacters(in: .whitespaces).isEmpty,
              let url = URL(string: raw) else { return nil }
        return url
    }

    static var isProxied: Bool { baseURL != nil }

    /// Served by the same Worker, so they cannot be broken by a deploy of something
    /// else and they are on an origin the app is already allowed to reach. The fallback
    /// is only ever hit by a build with no proxy configured, which cannot ship.
    private static let legalHome = URL(string: "https://coachjett-proxy.hlincontacts.workers.dev")!
    static var termsURL: String { (baseURL ?? legalHome).appendingPathComponent("legal/terms").absoluteString }
    static var privacyURL: String { (baseURL ?? legalHome).appendingPathComponent("legal/privacy").absoluteString }

    enum Route: String {
        case coach = "v1/coach"
        case meal = "v1/meal"
        /// A dry run of the gate. Answers only while attestation is not yet required.
        case attestCheck = "v1/attest/check"
    }

    /// A request to our proxy, carrying proof of who is asking but never a provider key.
    ///
    /// Synchronous, and therefore unattested. Everything that talks to the proxy is
    /// async and uses `attestedRequest`; this is the builder underneath it.
    static func request(_ route: Route, body: [String: Any]) throws -> URLRequest {
        guard let baseURL else { throw CoachError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(route.rawValue))
        request.httpMethod = "POST"
        request.timeoutInterval = route == .coach ? 120 : 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The server decides entitlement from this, rather than trusting a boolean.
        if let signed = Entitlement.signedTransaction {
            request.setValue(signed, forHTTPHeaderField: "x-jett-transaction")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// The same request, signed by the Secure Enclave.
    ///
    /// The body is signed along with a challenge the server just issued, so a captured
    /// assertion is good for exactly one request and cannot be pointed at a different
    /// question. On a simulator, where App Attest does not exist, this is the plain
    /// request and the development secret carries it.
    /// The client offers proof; the server decides whether it needed it.
    ///
    /// Never throws on a failure to attest. Registration needs a round trip and Apple's
    /// own service, either of which can be down, and the app refusing to send a message
    /// because it could not produce a signature the server is not currently asking for
    /// is a self-inflicted outage. When attestation is required the request still goes,
    /// and comes back 401, which is a real answer rather than a raw enum description.
    static func attestedRequest(_ route: Route, body: [String: Any]) async throws -> URLRequest {
        var request = try Self.request(route, body: body)
        guard let baseURL, AppAttest.isSupported, let payload = request.httpBody else {
            return request
        }
        // The purchase exactly as this request carries it, read back from the header
        // rather than from the cache again, which could have refreshed in between and
        // left the signature covering a different one.
        let purchase = request.value(forHTTPHeaderField: "x-jett-transaction")
        guard let proof = await AppAttest.proof(for: payload, purchase: purchase, baseURL: baseURL) else {
            return request
        }
        request.setValue(proof.keyID, forHTTPHeaderField: "x-jett-key-id")
        request.setValue(proof.challenge, forHTTPHeaderField: "x-jett-challenge")
        request.setValue(proof.assertion, forHTTPHeaderField: "x-jett-attestation")
        return request
    }

    /// Turns a proxy status into something the app already knows how to show.
    ///
    /// The statuses are the ones the Worker returns, and each maps onto an error the UI
    /// already renders, so the proxy needed no new failure states.
    /// Whether this install can prove itself to the proxy, and what went wrong if not.
    ///
    /// Runs the gate without being gated by it, so attestation can be confirmed working
    /// on a real device before it becomes the only way in.
    static func attestationCheck() async -> String {
        guard let baseURL else { return "No proxy configured" }
        guard AppAttest.isSupported else { return "Not available on this device" }
        do {
            let request = try await attestedRequest(.attestCheck, body: ["probe": true])
            guard request.value(forHTTPHeaderField: "x-jett-attestation") != nil else {
                return "The app could not build a proof: \(AppAttest.status)"
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                return "The check endpoint answered \(status). Deploy the server first."
            }
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            if object?["ok"] as? Bool == true { return "Working" }
            return (object?["reason"] as? String).map { "Rejected: \($0)" } ?? "Rejected"
        } catch {
            return "Could not reach the proxy: \(error.localizedDescription)"
        }
    }

    static func failure(status: Int, body: String, retryAfter: String?) -> CoachError {
        switch status {
        case 401, 501:
            // Not the user's problem and not something they can fix. `.notConfigured`
            // would tell them to add an API key in Profile, which is exactly the thing
            // the proxy exists to stop them ever needing.
            return .transport("Jett can't be reached right now. This one is on us.")
        case 402:
            return .declined("That's the last of the free answers. Jett is unlimited on a plan.")
        case 429:
            let seconds = retryAfter.flatMap(Int.init) ?? 12
            return .declined("One at a time. Try again in \(seconds)s.")
        case 503:
            return .transport("Jett can't be reached right now. Try again in a moment.")
        default:
            return .transport(body.isEmpty ? "Something went wrong (\(status))." : body)
        }
    }
}
