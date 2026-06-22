import Foundation

extension Notification.Name {
    static let directGenConfigChanged = Notification.Name("directGenConfigChanged")
}

enum DirectGenerationConfig {
    private static let enabledKey = "directGen.enabled"
    private static let imageModelKey = "directGen.imageModel"
    private static let videoModelKey = "directGen.videoModel"
    private static let suite = UserDefaults(suiteName: "io.palmier.pro") ?? .standard

    static var isEnabled: Bool {
        get { suite.bool(forKey: enabledKey) }
        set {
            suite.set(newValue, forKey: enabledKey)
            notifyChanged()
        }
    }

    static var imageModel: String {
        get { suite.string(forKey: imageModelKey) ?? "dall-e-3" }
        set {
            suite.set(newValue, forKey: imageModelKey)
            notifyChanged()
        }
    }

    // Reuse chat API credentials — same proxy, same key
    static var baseURL: String { CustomAPIKeychain.baseURL }
    static var apiKey: String? { CustomAPIKeychain.loadAPIKey() }

    static var isConfigured: Bool {
        isEnabled && !baseURL.isEmpty && !(apiKey ?? "").isEmpty
    }

    static var videoModel: String {
        get { suite.string(forKey: videoModelKey) ?? "MiniMax-Hailuo-2.3" }
        set {
            suite.set(newValue, forKey: videoModelKey)
            notifyChanged()
        }
    }

    static func makeImageClient() -> DirectImageGenerationClient? {
        guard isConfigured, let key = apiKey, !imageModel.isEmpty else { return nil }
        return DirectImageGenerationClient(baseURL: baseURL, apiKey: key, model: imageModel)
    }

    static func makeVideoClient() -> DirectVideoGenerationClient? {
        guard isConfigured, let key = apiKey, !videoModel.isEmpty else { return nil }
        return DirectVideoGenerationClient(baseURL: baseURL, apiKey: key, model: videoModel)
    }

    private static func notifyChanged() {
        NotificationCenter.default.post(name: .directGenConfigChanged, object: nil)
        Task { @MainActor in ModelCatalog.shared.refreshDirectModels() }
    }
}
