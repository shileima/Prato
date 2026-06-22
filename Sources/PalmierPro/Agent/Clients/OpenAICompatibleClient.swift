import Foundation

struct OpenAICompatibleClient: AgentClient {
    let baseURL: String
    let apiKey: String
    let model: String
    var maxTokens: Int = 8192

    func stream(
        system: String,
        tools: [AnthropicToolSchema],
        messages: [AnthropicMessage]
    ) -> AsyncThrowingStream<AnthropicStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(system: system, tools: tools, messages: messages, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(
        system: String,
        tools: [AnthropicToolSchema],
        messages: [AnthropicMessage],
        continuation: AsyncThrowingStream<AnthropicStreamEvent, Error>.Continuation
    ) async throws {
        guard !apiKey.isEmpty else { throw OpenAIClientError.missingAPIKey }
        guard !baseURL.isEmpty else { throw OpenAIClientError.missingBaseURL }

        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let endpoint = URL(string: "\(base)/chat/completions") else {
            throw OpenAIClientError.invalidBaseURL
        }

        let openAIMessages = buildOpenAIMessages(system: system, messages: messages)
        let openAITools = buildOpenAITools(tools: tools)

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": openAIMessages,
        ]
        if !openAITools.isEmpty {
            body["tools"] = openAITools
            body["tool_choice"] = "auto"
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line + "\n" }
            throw OpenAIClientError.httpError(status: http.statusCode, body: errorBody)
        }

        try await parseOpenAIStream(bytes: bytes, continuation: continuation)
    }

    // MARK: - Message conversion (Anthropic → OpenAI)

    private func buildOpenAIMessages(system: String, messages: [AnthropicMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []

        if !system.isEmpty {
            result.append(["role": "system", "content": system])
        }

        for msg in messages {
            let converted = convertMessage(msg)
            result.append(contentsOf: converted)
        }
        return result
    }

    private func convertMessage(_ msg: AnthropicMessage) -> [[String: Any]] {
        switch msg.role {
        case .user:
            return convertUserMessage(msg.content)
        case .assistant:
            return convertAssistantMessage(msg.content)
        }
    }

    // User messages may have text blocks and tool_result blocks.
    // Tool results become separate "tool" role messages in OpenAI format.
    private func convertUserMessage(_ content: [[String: Any]]) -> [[String: Any]] {
        var toolMessages: [[String: Any]] = []
        var textParts: [String] = []

        for block in content {
            guard let type = block["type"] as? String else { continue }
            switch type {
            case "text":
                if let text = block["text"] as? String {
                    textParts.append(text)
                }
            case "tool_result":
                let toolCallId = block["tool_use_id"] as? String ?? ""
                let resultContent = extractToolResultText(block["content"])
                toolMessages.append([
                    "role": "tool",
                    "tool_call_id": toolCallId,
                    "content": resultContent,
                ])
            default:
                break
            }
        }

        var result = toolMessages
        let joined = textParts.joined(separator: "\n")
        if !joined.isEmpty {
            result.append(["role": "user", "content": joined])
        }
        // If only tool results and no user text, don't append an empty user message
        return result
    }

    private func extractToolResultText(_ content: Any?) -> String {
        if let text = content as? String { return text }
        if let arr = content as? [[String: Any]] {
            return arr.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n")
        }
        if let data = try? JSONSerialization.data(withJSONObject: content as Any),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
        return ""
    }

    // Assistant messages may have text blocks and tool_use blocks.
    private func convertAssistantMessage(_ content: [[String: Any]]) -> [[String: Any]] {
        var textParts: [String] = []
        var toolCalls: [[String: Any]] = []

        for block in content {
            guard let type = block["type"] as? String else { continue }
            switch type {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty { textParts.append(text) }
            case "tool_use":
                let id = block["id"] as? String ?? UUID().uuidString
                let name = block["name"] as? String ?? ""
                let input = block["input"]
                let args: String
                if let inputDict = input,
                   let data = try? JSONSerialization.data(withJSONObject: inputDict),
                   let str = String(data: data, encoding: .utf8) {
                    args = str
                } else {
                    args = "{}"
                }
                toolCalls.append([
                    "id": id,
                    "type": "function",
                    "function": ["name": name, "arguments": args],
                ])
            default:
                break
            }
        }

        var msg: [String: Any] = ["role": "assistant"]
        // Omit content entirely when empty — some providers (e.g. AWS Bedrock) reject empty strings
        let joined = textParts.joined(separator: "\n")
        if !joined.isEmpty {
            msg["content"] = joined
        }
        if !toolCalls.isEmpty {
            msg["tool_calls"] = toolCalls
        }
        return [msg]
    }

    // MARK: - Tool schema conversion (Anthropic → OpenAI)

    private func buildOpenAITools(tools: [AnthropicToolSchema]) -> [[String: Any]] {
        tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": tool.inputSchema,
                ] as [String: Any],
            ]
        }
    }

    // MARK: - OpenAI SSE → Anthropic events

    private func parseOpenAIStream(
        bytes: URLSession.AsyncBytes,
        continuation: AsyncThrowingStream<AnthropicStreamEvent, Error>.Continuation
    ) async throws {
        // Per-call tool accumulator: index → (id, name, json)
        var pendingTools: [Int: (id: String, name: String, json: String)] = [:]

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data: ") else { continue }
            let payload = line.dropFirst("data: ".count).trimmingCharacters(in: .whitespaces)
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = event["choices"] as? [[String: Any]],
                  let choice = choices.first else { continue }

            let delta = choice["delta"] as? [String: Any]
            let finishReason = choice["finish_reason"] as? String

            // Text content
            if let text = delta?["content"] as? String, !text.isEmpty {
                continuation.yield(.textDelta(text))
            }

            // Tool calls
            if let toolCallDeltas = delta?["tool_calls"] as? [[String: Any]] {
                for tcDelta in toolCallDeltas {
                    guard let index = tcDelta["index"] as? Int else { continue }
                    let id = tcDelta["id"] as? String ?? ""
                    let fn = tcDelta["function"] as? [String: Any]
                    let name = fn?["name"] as? String ?? ""
                    let argsChunk = fn?["arguments"] as? String ?? ""

                    if var acc = pendingTools[index] {
                        acc.json += argsChunk
                        pendingTools[index] = acc
                    } else {
                        pendingTools[index] = (id: id, name: name, json: argsChunk)
                    }
                }
            }

            // Finish
            if let reason = finishReason, !reason.isEmpty, reason != "null" {
                // Flush any accumulated tool calls in index order
                for (_, acc) in pendingTools.sorted(by: { $0.key < $1.key }) {
                    let json = acc.json.isEmpty ? "{}" : acc.json
                    continuation.yield(.toolUseComplete(id: acc.id, name: acc.name, inputJSON: json))
                }
                pendingTools.removeAll()

                let stopReason: AnthropicStopReason
                switch reason {
                case "stop": stopReason = .endTurn
                case "tool_calls": stopReason = .toolUse
                case "length": stopReason = .maxTokens
                default: stopReason = .other
                }
                continuation.yield(.messageStop(stopReason: stopReason))
            }
        }
    }
}

enum OpenAIClientError: LocalizedError {
    case missingAPIKey
    case missingBaseURL
    case invalidBaseURL
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "未设置自定义 API Key。"
        case .missingBaseURL: "未设置自定义 API 地址。"
        case .invalidBaseURL: "自定义 API 地址格式无效。"
        case .httpError(let s, let b): "API 错误 (\(s)): \(b.prefix(500))"
        }
    }
}
