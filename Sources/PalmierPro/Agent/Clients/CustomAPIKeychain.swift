import Foundation

extension Notification.Name {
    static let customAPIConfigChanged = Notification.Name("customAPIConfigChanged")
}

enum CustomAPIKeychain {
    private static let apiKeyAccount = "custom-api-key"
    private static let baseURLKey = "customAPIBaseURL"
    private static let modelKey = "customAPIModel"
    private static let enabledKey = "customAPIEnabled"
    // Explicit suite so reads work regardless of Bundle.main.bundleIdentifier
    private static let suite = UserDefaults(suiteName: "io.palmier.pro") ?? .standard

    static func saveAPIKey(_ key: String) {
        KeychainStore.save(key, account: apiKeyAccount)
        notifyChanged()
    }

    static func loadAPIKey() -> String? {
        // Env var fallback for dev builds
        if let env = ProcessInfo.processInfo.environment["CUSTOM_API_KEY"],
           !env.isEmpty { return env }
        return KeychainStore.load(account: apiKeyAccount)
    }

    static func deleteAPIKey() {
        KeychainStore.delete(account: apiKeyAccount)
        notifyChanged()
    }

    static var baseURL: String {
        get {
            ProcessInfo.processInfo.environment["CUSTOM_API_BASE_URL"]
                ?? suite.string(forKey: baseURLKey)
                ?? ""
        }
        set {
            suite.set(newValue, forKey: baseURLKey)
            notifyChanged()
        }
    }

    static var model: String {
        get {
            ProcessInfo.processInfo.environment["CUSTOM_API_MODEL"]
                ?? suite.string(forKey: modelKey)
                ?? "claude-opus-4-6"
        }
        set { suite.set(newValue, forKey: modelKey) }
    }

    static var isEnabled: Bool {
        get {
            if ProcessInfo.processInfo.environment["CUSTOM_API_KEY"] != nil { return true }
            return suite.bool(forKey: enabledKey)
        }
        set {
            suite.set(newValue, forKey: enabledKey)
            notifyChanged()
        }
    }

    static var isConfigured: Bool {
        isEnabled && !baseURL.isEmpty && !(loadAPIKey() ?? "").isEmpty
    }

    private static func notifyChanged() {
        NotificationCenter.default.post(name: .customAPIConfigChanged, object: nil)
    }
}
