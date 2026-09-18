import Foundation

/// Talks to the Messages API over URLSession. Swift has no first-party Anthropic SDK,
/// so this is the documented raw HTTP shape.
struct ClaudeCoachProvider: CoachProvider {

    /// Only derived aggregates are sent, never raw health records (privacy posture C3).
    static let model = "claude-opus-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    var apiKey: String? { Keychain.apiKey }
    var isConfigured: Bool { (apiKey?.isEmpty == false) }

    func stream(messages: [CoachMessage], context: CoachContext)
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let apiKey, !apiKey.isEmpty else {
                    continuation.finish(throwing: CoachError.notConfigured); return
                }

                var request = URLRequest(url: Self.endpoint)
                request.httpMethod = "POST"
                request.timeoutInterval = 120
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

                let body: [String: Any] = [
                    "model": Self.model,
                    "max_tokens": 1024,          // Answers are short by design.
                    "stream": true,
                    "system": CoachPrompt.system(context: context),
                    "output_config": ["effort": "medium"],
                    // Route around a safety refusal rather than dead-ending the user.
                    "betas": ["server-side-fallback-2026-07-01"],
                    "fallbacks": "default",
                    "messages": messages.map { ["role": $0.role.rawValue, "content": $0.text] },
                ]

                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        continuation.finish(throwing: CoachError.transport(
                            "The coach service returned \(http.statusCode)."))
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]",
                              let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data)
                                  as? [String: Any] else { continue }

                        switch event["type"] as? String {
                        case "content_block_delta":
                            if let delta = event["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(text)
                            }

                        case "message_delta":
                            // A safety refusal arrives as HTTP 200, so it has to be read
                            // off the stop reason rather than caught as an error.
                            if let delta = event["delta"] as? [String: Any],
                               delta["stop_reason"] as? String == "refusal" {
                                continuation.finish(throwing: CoachError.declined(
                                    "The coach declined to answer that one. Try rephrasing, "
                                    + "or ask about your training instead."))
                                return
                            }

                        case "error":
                            let message = (event["error"] as? [String: Any])?["message"] as? String
                            continuation.finish(throwing: CoachError.transport(
                                message ?? "The coach stopped unexpectedly."))
                            return

                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: CoachError.transport(error.localizedDescription))
                }
            }
        }
    }
}

/// The key is the user's own credential and belongs in the Keychain, not in UserDefaults
/// and not in the source.
enum Keychain {
    private static let service = "com.readiness.barbell.anthropic"
    private static let account = "api-key"

    static var apiKey: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func setAPIKey(_ key: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !key.isEmpty else { return true }
        var insert = base
        insert[kSecValueData as String] = Data(key.utf8)
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }
}
