import Foundation

/// Talks to the Messages API over URLSession. Swift has no first-party Anthropic SDK,
/// so this is the documented raw HTTP shape.
struct ClaudeCoachProvider: CoachProvider {

    /// Jett explains a decision the rules engine already made and occasionally calls one
    /// small tool. That is not frontier reasoning, and Opus costs a multiple of Sonnet
    /// per token for it. Flip this one constant back if the writing ever feels thin.
    static let model = "claude-sonnet-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// Rounds of tool use before the loop gives up, so a confused model cannot spin.
    static let maximumToolRounds = 3
    /// How much conversation travels with each request. Everything before this is
    /// dropped: the context block already carries the state of the world, so old turns
    /// are paid for on every request while adding almost nothing.
    static let maximumHistoryMessages = 16

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

                var wire = CoachRequest.trim(
                    messages.map { ["role": $0.role.rawValue, "content": $0.text] },
                    to: Self.maximumHistoryMessages)

                do {
                    for round in 0..<Self.maximumToolRounds {
                        // The last round is answered without tools, so the model has to
                        // put its conclusion in prose. Offering a tool it has no room to
                        // follow up on leaves the user holding a proposal and no reply.
                        let isFinal = round == Self.maximumToolRounds - 1
                        let turn = try await runTurn(apiKey: apiKey, context: context,
                                                     messages: wire, offersTools: !isFinal,
                                                     continuation: continuation)
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
                         offersTools: Bool,
                         continuation: AsyncThrowingStream<CoachEvent, Error>.Continuation)
        async throws -> Turn {

        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = CoachRequest.body(model: Self.model,
                                     rules: CoachPrompt.rules,
                                     data: CoachPrompt.data(context: context),
                                     messages: messages,
                                     offersTools: offersTools)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // The API says why in the body. Throwing only the status code turns a
            // fixable 400 into a mystery.
            var detail = ""
            for try await line in bytes.lines { detail += line }
            throw CoachError.transport(Self.describe(status: http.statusCode, body: detail))
        }

        var turn = Turn()
        var usage = CoachUsage()
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
            case "message_start":
                // Recorded because a bill you cannot attribute is a bill you cannot cut.
                if let message = event["message"] as? [String: Any],
                   let reported = message["usage"] as? [String: Any] {
                    usage.absorb(reported)
                }

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
                if let reported = event["usage"] as? [String: Any] { usage.absorb(reported) }
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

        usage.log()

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

    /// Turns an HTTP failure into something the user, or a log, can act on.
    private static func describe(status: Int, body: String) -> String {
        let reported = body
            .split(separator: "\n")
            .compactMap { line -> String? in
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let error = object["error"] as? [String: Any] else { return nil }
                return error["message"] as? String
            }
            .first

        switch status {
        case 401, 403: return "The coach key was rejected. Check it in Profile."
        case 429:      return "Too many requests to the coach right now. Try again shortly."
        case 529:      return "The coach service is overloaded. Try again shortly."
        default:       return reported ?? "The coach service returned \(status)."
        }
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
    private static let service = "com.coachjett.app.anthropic"
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
