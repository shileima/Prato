import Foundation

struct DirectImageGenerationClient: Sendable {
    let baseURL: String
    let apiKey: String
    let model: String

    func generate(prompt: String, count: Int, aspectRatio: String) async throws -> [URL] {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let endpoint = URL(string: "\(base)/images/generations") else {
            throw DirectGenerationError.invalidBaseURL
        }

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "n": count,
            "size": Self.size(for: aspectRatio),
            "response_format": "url",
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DirectGenerationError.httpError(status: http.statusCode, body: body)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else {
            throw DirectGenerationError.invalidResponse
        }

        let urls = items.compactMap { $0["url"] as? String }.compactMap { URL(string: $0) }
        guard !urls.isEmpty else { throw DirectGenerationError.noResults }
        return urls
    }

    private static func size(for aspectRatio: String) -> String {
        switch aspectRatio {
        case "1:1":  return "1024x1024"
        case "16:9": return "1792x1024"
        case "9:16": return "1024x1792"
        case "4:3":  return "1365x1024"
        case "3:4":  return "1024x1365"
        case "3:2":  return "1536x1024"
        case "2:3":  return "1024x1536"
        default:     return "1024x1024"
        }
    }
}

enum DirectGenerationError: LocalizedError {
    case invalidBaseURL
    case httpError(status: Int, body: String)
    case invalidResponse
    case noResults

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:             "API 地址格式无效。"
        case .httpError(let s, let b):    "API 错误 (\(s)): \(b.prefix(500))"
        case .invalidResponse:            "API 返回格式异常。"
        case .noResults:                  "API 未返回任何图片。"
        }
    }
}

// MARK: - Video generation client

struct DirectVideoTaskStatus: Sendable {
    let taskId: String
    let status: String        // "in_progress" | "completed" | "failed"
    let progress: Int         // 0-100
    let videoURL: URL?
    let errorMessage: String?
}

struct DirectVideoGenerationClient: Sendable {
    let baseURL: String
    let apiKey: String
    let model: String

    // POST /v1/videos → task_id
    func submitTask(
        prompt: String,
        duration: Int,
        resolution: String?,
        firstFrameURL: String? = nil
    ) async throws -> String {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let endpoint = URL(string: "\(base)/videos") else {
            throw DirectGenerationError.invalidBaseURL
        }
        var body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "duration": duration,
        ]
        if let res = resolution, !res.isEmpty { body["resolution"] = res }
        if let img = firstFrameURL, !img.isEmpty { body["image"] = img }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw DirectGenerationError.httpError(status: http.statusCode, body: bodyStr)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DirectGenerationError.invalidResponse
        }
        // Check for API-level error (e.g. invalid params)
        if let msg = json["message"] as? String, json["code"] != nil {
            throw DirectGenerationError.httpError(status: 400, body: msg)
        }
        guard let taskId = (json["task_id"] ?? json["id"]) as? String, !taskId.isEmpty else {
            throw DirectGenerationError.invalidResponse
        }
        return taskId
    }

    // GET /v1/videos/{task_id} → status
    func pollTask(taskId: String) async throws -> DirectVideoTaskStatus {
        let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        guard let endpoint = URL(string: "\(base)/videos/\(taskId)") else {
            throw DirectGenerationError.invalidBaseURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw DirectGenerationError.httpError(status: http.statusCode, body: bodyStr)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DirectGenerationError.invalidResponse
        }

        let status   = json["status"] as? String ?? "unknown"
        let progress = json["progress"] as? Int ?? 0
        let metadata = json["metadata"] as? [String: Any]
        let urlStr   = metadata?["url"] as? String ?? ""
        let videoURL = urlStr.isEmpty ? nil : URL(string: urlStr)
        let errorMsg = (json["error"] as? [String: Any])?["message"] as? String

        return DirectVideoTaskStatus(
            taskId: taskId,
            status: status,
            progress: progress,
            videoURL: videoURL,
            errorMessage: errorMsg
        )
    }
}

// MARK: - VideoModelConfig factory for direct-API models

extension VideoModelConfig {
    static func direct(modelId: String, displayName: String, durations: [Int], resolutions: [String]) -> VideoModelConfig? {
        let json: [String: Any] = [
            "id": modelId,
            "kind": "video",
            "displayName": displayName,
            "allowedEndpoints": [String](),
            "responseShape": "video",
            "uiCapabilities": [
                "durations": durations,
                "resolutions": resolutions,
                "aspectRatios": ["16:9", "9:16", "1:1"],
                "supportsFirstFrame": false,
                "supportsLastFrame": false,
                "maxReferenceImages": 0,
                "maxReferenceVideos": 0,
                "maxReferenceAudios": 0,
                "framesAndReferencesExclusive": false,
                "referenceTagNoun": "",
                "requiresSourceVideo": false,
                "requiresReferenceImage": false,
            ] as [String: Any],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let entry = try? JSONDecoder().decode(CatalogEntry.self, from: data),
              case .video(let caps) = entry.uiCapabilities else { return nil }
        return VideoModelConfig(entry: entry, caps: caps)
    }
}

// MARK: - ImageModelConfig factory for direct-API models

extension ImageModelConfig {
    static func direct(modelId: String, displayName: String) -> ImageModelConfig? {
        let json: [String: Any] = [
            "id": modelId,
            "kind": "image",
            "displayName": displayName,
            "allowedEndpoints": [String](),
            "responseShape": "images",
            "uiCapabilities": [
                "aspectRatios": ["1:1", "16:9", "9:16", "4:3", "3:4", "3:2", "2:3"],
                "supportsImageReference": false,
                "maxImages": 4,
            ] as [String: Any],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let entry = try? JSONDecoder().decode(CatalogEntry.self, from: data),
              case .image(let caps) = entry.uiCapabilities else { return nil }
        return ImageModelConfig(entry: entry, caps: caps)
    }
}
