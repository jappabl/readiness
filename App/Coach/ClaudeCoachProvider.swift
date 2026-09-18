import Foundation

/// Talks to the Messages API over URLSession. Swift has no first-party Anthropic SDK,
/// so this is the documented raw HTTP shape.
struct ClaudeCoachProvider: CoachProvider {

    static let model = "claude-opus-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// Rounds of tool use before the loop gives up, so a confused model cannot spin.
    static let maximumToolRounds = 3

    var apiKey: String? { Keychain.apiKey }
    var isConfigured: Bool { (apiKey?.isEmpty == false) }

    func stream(messages: [CoachMessage],
                context: CoachContext,
                applyTool: @escaping @Sendable (CoachToolCall) async -> String)
        -> AsyncThrowingStream<CoachEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let apiKey, !apiKey.isEmpty else {
                    continuation.finish(throwing: CoachError.notConfigured); return
                }

                var wire: [[String: Any]] = messages.map {
                    ["role": $0.role.rawValue, "content": $0.text]
                }

                do {
                    for _ in 0..<Self.maximumToolRounds {
                        let turn = try await runTurn(apiKey: apiKey, context: context,
                                                     messages: wire, continuation: continuation)
                        guard let call = turn.toolCall else { continuation.finish(); return }

                        continuation.yield(.toolCall(call))
                        let result = await applyTool(call)

                        wire.append(["role": "assistant", "content": turn.assistantBlocks])
                        wire.append(["role": "user", "content": [[
                            "type": "tool_result",
                            "tool_use_id": call.id,
                            "content": result,
                        ]]])
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - One request

    private struct Turn {
        var toolCall: CoachToolCall?
        var assistantBlocks: [[String: Any]] = []
    }

    private func runTurn(apiKey: String, context: CoachContext, messages: [[String: Any]],
                         continuation: AsyncThrowingStream<CoachEvent, Error>.Continuation)
        async throws -> Turn {

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 1024,
            "stream": true,
            "system": CoachPrompt.system(context: context),
            "output_config": ["effort": "medium"],
            "tools": [CoachTools.schema],
            // Route around a safety refusal rather than dead-ending the user.
            "betas": ["server-side-fallback-2026-07-01"],
            "fallbacks": "default",
            "messages": messages,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw CoachError.transport("The coach service returned \(http.statusCode).")
        }

        var turn = Turn()
        var text = ""
        var toolID = ""
        var toolJSON = ""
        var currentIsTool = false

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            guard payload != "[DONE]", let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            switch event["type"] as? String {
            case "content_block_start":
                let block = event["content_block"] as? [String: Any]
                currentIsTool = (block?["type"] as? String) == "tool_use"
                if currentIsTool {
                    toolID = block?["id"] as? String ?? ""
                    toolJSON = ""
                }

            case "content_block_delta":
                let delta = event["delta"] as? [String: Any]
                if let chunk = delta?["text"] as? String {
                    text += chunk
                    continuation.yield(.text(chunk))
                }
                if let partial = delta?["partial_json"] as? String { toolJSON += partial }

            case "content_block_stop":
                if currentIsTool { turn.toolCall = parse(id: toolID, json: toolJSON) }
                currentIsTool = false

            case "message_delta":
                // A safety refusal arrives as HTTP 200, so it is read off the stop reason
                // rather than caught as an error.
                if (event["delta"] as? [String: Any])?["stop_reason"] as? String == "refusal" {
                    throw CoachError.declined(
                        "The coach declined to answer that one. Try rephrasing, or ask about "
                        + "your training instead.")
                }

            case "error":
                let message = (event["error"] as? [String: Any])?["message"] as? String
                throw CoachError.transport(message ?? "The coach stopped unexpectedly.")

            default:
                break
            }
        }

        // Replay the assistant's own turn verbatim when continuing after a tool.
        if turn.toolCall != nil {
            if !text.isEmpty { turn.assistantBlocks.append(["type": "text", "text": text]) }
            turn.assistantBlocks.append([
                "type": "tool_use",
                "id": toolID,
                "name": CoachTools.adjustSession,
                "input": (try? JSONSerialization.jsonObject(with: Data(toolJSON.utf8)))
                    as? [String: Any] ?? [:],
            ])
        }
        return turn
    }

    /// The model's input is untrusted. Anything it cannot justify is dropped.
    private func parse(id: String, json: String) -> CoachToolCall? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = object["action"] as? String,
              let adjustment = CoachTools.adjustment(action: action,
                                                     percent: object["percent"] as? Int,
                                                     rir: object["rir"] as? Int)
        else { return nil }
        return CoachToolCall(id: id, adjustment: adjustment,
                             reason: (object["reason"] as? String) ?? "")
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
