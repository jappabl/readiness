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

    /// Stands in for App Attest until the project has a team id to attest against.
    /// Debug builds only: a shipped app must never carry a shared secret.
    static var developmentSecret: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["JETT_DEV_SECRET"]
        #else
        nil
        #endif
    }

    enum Route: String {
        case coach = "v1/coach"
        case meal = "v1/meal"
    }

    /// A request to our proxy, carrying proof of who is asking but never a provider key.
    static func request(_ route: Route, body: [String: Any]) throws -> URLRequest {
        guard let baseURL else { throw CoachError.notConfigured }
        var request = URLRequest(url: baseURL.appendingPathComponent(route.rawValue))
        request.httpMethod = "POST"
        request.timeoutInterval = route == .coach ? 120 : 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let developmentSecret {
            request.setValue(developmentSecret, forHTTPHeaderField: "x-jett-dev-secret")
        }
        // The server decides entitlement from this, rather than trusting a boolean.
        if let signed = Entitlement.signedTransaction {
            request.setValue(signed, forHTTPHeaderField: "x-jett-transaction")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Turns a proxy status into something the app already knows how to show.
    ///
    /// The statuses are the ones the Worker returns, and each maps onto an error the UI
    /// already renders, so the proxy needed no new failure states.
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
