import AppKit
import SwiftUI

struct AgentPane: View {
    @Bindable private var appState = AppState.shared
    @State private var hasKey: Bool = false
    @State private var maskedKey: String = ""
    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    // Custom API state
    @State private var customEnabled: Bool = false
    @State private var customBaseURL: String = ""
    @State private var customDraftKey: String = ""
    @State private var customHasKey: Bool = false
    @State private var customMaskedKey: String = ""
    @State private var customModel: String = ""
    @State private var customTestStatus: CustomTestStatus = .idle
    @FocusState private var customKeyFocused: Bool

    // Direct generation state
    @State private var directGenEnabled: Bool = false
    @State private var directImageModel: String = ""
    @State private var directVideoModel: String = ""
    @State private var directGenTestStatus: CustomTestStatus = .idle

    private let consoleURL = URL(string: "https://console.anthropic.com/settings/keys")!

    enum CustomTestStatus {
        case idle, testing, success(String), failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            customAPISection
            Divider().overlay(AppTheme.Border.subtleColor)
            directGenSection
            Divider().overlay(AppTheme.Border.subtleColor)
            apiKeySection
            Divider().overlay(AppTheme.Border.subtleColor)
            mcpSection
        }
        .onAppear(perform: refresh)
    }

    // MARK: - Custom API Section

    private var customAPISection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            customAPIHeader
            customAPIFields
        }
    }

    private var customAPIHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack {
                Text("自定义模型 API")
                    .font(.system(size: AppTheme.FontSize.md, weight: .medium))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                Spacer()
                Toggle("", isOn: $customEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: customEnabled) { _, _ in applyCustomSettings() }
            }
            Text("接入 OpenAI 兼容 API（支持 Claude、Gemini、DeepSeek 等），优先级高于 Anthropic Key。")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.tertiaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var customAPIFields: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            // Base URL
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("API 地址")
                    .font(.system(size: AppTheme.FontSize.xs, weight: .medium))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                TextField("https://api.openai.com/v1", text: $customBaseURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.smMd)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .fill(Color.black.opacity(AppTheme.Opacity.muted))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin)
                    )
                    .onSubmit { applyCustomSettings() }
            }

            // API Key
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("API Key")
                    .font(.system(size: AppTheme.FontSize.xs, weight: .medium))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                HStack(spacing: AppTheme.Spacing.sm) {
                    SecureField(customHasKey ? customMaskedKey : "sk-...", text: $customDraftKey)
                        .textFieldStyle(.plain)
                        .focused($customKeyFocused)
                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                        .onSubmit(saveCustomAPIKey)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.smMd)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .fill(Color.black.opacity(AppTheme.Opacity.muted))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin)
                        )
                    let trimmedKey = customDraftKey.trimmingCharacters(in: .whitespaces)
                    if !trimmedKey.isEmpty {
                        Button("保存", action: saveCustomAPIKey)
                            .buttonStyle(.capsule(.prominent, size: .regular))
                            .controlSize(.large)
                    } else if customHasKey {
                        Button(action: removeCustomAPIKey) {
                            Image(systemName: "trash")
                                .font(.system(size: AppTheme.FontSize.md))
                                .foregroundStyle(AppTheme.Text.secondaryColor)
                                .frame(width: AppTheme.IconSize.md, height: AppTheme.IconSize.md)
                        }
                        .buttonStyle(.capsule(.secondary, size: .regular))
                        .controlSize(.large)
                        .help("删除 API Key")
                    }
                }
            }

            // Model name
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text("模型名称")
                    .font(.system(size: AppTheme.FontSize.xs, weight: .medium))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                TextField("claude-opus-4-6", text: $customModel)
                    .textFieldStyle(.plain)
                    .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                    .foregroundStyle(AppTheme.Text.primaryColor)
                    .padding(.horizontal, AppTheme.Spacing.md)
                    .padding(.vertical, AppTheme.Spacing.smMd)
                    .background(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .fill(Color.black.opacity(AppTheme.Opacity.muted))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                            .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin)
                    )
                    .onSubmit { applyCustomSettings() }
            }

            // Test + status
            HStack(spacing: AppTheme.Spacing.sm) {
                Button(action: { applyCustomSettings(); testCustomAPI() }) {
                    HStack(spacing: AppTheme.Spacing.xs) {
                        if case .testing = customTestStatus {
                            ProgressView().controlSize(.mini)
                        }
                        Text("测试连接")
                    }
                }
                .buttonStyle(.capsule(.secondary, size: .regular))
                .controlSize(.large)
                .disabled({ if case .testing = customTestStatus { return true }; return false }())

                switch customTestStatus {
                case .idle: EmptyView()
                case .testing: EmptyView()
                case .success(let msg):
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(.green)
                case .failure(let msg):
                    Label(msg, systemImage: "xmark.circle.fill")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
            }
        }
        .opacity(customEnabled ? 1 : 0.5)
        .disabled(!customEnabled)
    }

    // MARK: - Direct Generation Section

    private var directGenSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            // Header row — always interactive so the Toggle can be clicked
            HStack {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("直连生成 API")
                        .font(.system(size: AppTheme.FontSize.md, weight: .medium))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                    Text("绕过 Prato，通过自定义 API 直接生成图片。复用上方的 API 地址和 Key。")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $directGenEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: directGenEnabled) { _, _ in applyDirectGenSettings() }
            }

            // Fields — disabled when toggle is off
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("图片生成模型")
                        .font(.system(size: AppTheme.FontSize.xs, weight: .medium))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                    TextField("dall-e-3", text: $directImageModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.smMd)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .fill(Color.black.opacity(AppTheme.Opacity.muted))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin)
                        )
                        .onSubmit { applyDirectGenSettings() }
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("视频生成模型")
                        .font(.system(size: AppTheme.FontSize.xs, weight: .medium))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                    TextField("MiniMax-Hailuo-2.3", text: $directVideoModel)
                        .textFieldStyle(.plain)
                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                        .padding(.horizontal, AppTheme.Spacing.md)
                        .padding(.vertical, AppTheme.Spacing.smMd)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .fill(Color.black.opacity(AppTheme.Opacity.muted))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin)
                        )
                        .onSubmit { applyDirectGenSettings() }
                }

                HStack(spacing: AppTheme.Spacing.sm) {
                    Button(action: { applyDirectGenSettings(); testDirectGenAPI() }) {
                        HStack(spacing: AppTheme.Spacing.xs) {
                            if case .testing = directGenTestStatus { ProgressView().controlSize(.mini) }
                            Text("测试生成")
                        }
                    }
                    .buttonStyle(.capsule(.secondary, size: .regular))
                    .controlSize(.large)
                    .disabled({ if case .testing = directGenTestStatus { return true }; return false }())

                    switch directGenTestStatus {
                    case .idle: EmptyView()
                    case .testing: EmptyView()
                    case .success(let msg):
                        Label(msg, systemImage: "checkmark.circle.fill")
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(.green)
                    case .failure(let msg):
                        Label(msg, systemImage: "xmark.circle.fill")
                            .font(.system(size: AppTheme.FontSize.sm))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                    }
                    Spacer()
                }
            }
            .opacity(directGenEnabled ? 1 : 0.5)
            .disabled(!directGenEnabled)
        }
    }

    private func applyDirectGenSettings() {
        DirectGenerationConfig.isEnabled = directGenEnabled
        DirectGenerationConfig.imageModel = directImageModel.trimmingCharacters(in: .whitespaces)
        DirectGenerationConfig.videoModel = directVideoModel.trimmingCharacters(in: .whitespaces)
    }

    private func testDirectGenAPI() {
        applyDirectGenSettings()
        guard DirectGenerationConfig.isConfigured else {
            directGenTestStatus = .failure("请先在上方配置 API 地址和 Key，并启用直连生成")
            return
        }
        guard let client = DirectGenerationConfig.makeImageClient() else {
            directGenTestStatus = .failure("配置不完整")
            return
        }
        directGenTestStatus = .testing
        Task {
            do {
                // Use a minimal 1-image request with a simple prompt to test connectivity
                _ = try await client.generate(prompt: "a simple test image", count: 1, aspectRatio: "1:1")
                directGenTestStatus = .success("连接成功，图片生成可用")
            } catch {
                directGenTestStatus = .failure(error.localizedDescription)
            }
        }
    }

    // MARK: - Anthropic API Section

    private var apiKeySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            header
            keyField
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Anthropic API Key")
                .font(.system(size: AppTheme.FontSize.md, weight: .medium))
                .foregroundStyle(AppTheme.Text.primaryColor)

            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                Text("使用自己的 API Key 进行 AI 对话，安全存储于 macOS 钥匙串。")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: { NSWorkspace.shared.open(consoleURL, configuration: .init(), completionHandler: nil) }) {
                    HStack(spacing: 2) {
                        Text("获取 Anthropic API Key")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: AppTheme.FontSize.xs, weight: .semibold))
                    }
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Accent.primary)
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
    }

    private var keyField: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            fieldBox
            trailingControl
        }
    }

    private var fieldBox: some View {
        SecureField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
            .foregroundStyle(AppTheme.Text.primaryColor)
            .onSubmit(save)
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.smMd)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(Color.black.opacity(AppTheme.Opacity.muted))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .strokeBorder(
                        isFocused ? AppTheme.Border.primaryColor : AppTheme.Border.subtleColor,
                        lineWidth: AppTheme.BorderWidth.thin
                    )
            )
            .animation(.easeOut(duration: AppTheme.Anim.hover), value: isFocused)
    }

    private var placeholder: String {
        hasKey ? maskedKey : "sk-ant-..."
    }

    @ViewBuilder
    private var trailingControl: some View {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            Button("保存", action: save)
                .buttonStyle(.capsule(.prominent, size: .regular))
                .controlSize(.large)
        } else if hasKey {
            Button(action: remove) {
                Image(systemName: "trash")
                    .font(.system(size: AppTheme.FontSize.md))
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                    .frame(width: AppTheme.IconSize.md, height: AppTheme.IconSize.md)
            }
            .buttonStyle(.capsule(.secondary, size: .regular))
            .controlSize(.large)
            .help("删除 API Key")
        }
    }

    private func refresh() {
        let key = AnthropicKeychain.load() ?? ""
        hasKey = !key.isEmpty
        maskedKey = mask(key)

        customEnabled = CustomAPIKeychain.isEnabled
        customBaseURL = CustomAPIKeychain.baseURL
        customModel = CustomAPIKeychain.model
        let cKey = CustomAPIKeychain.loadAPIKey() ?? ""
        customHasKey = !cKey.isEmpty
        customMaskedKey = mask(cKey)

        directGenEnabled = DirectGenerationConfig.isEnabled
        directImageModel = DirectGenerationConfig.imageModel
        directVideoModel = DirectGenerationConfig.videoModel
    }

    private func save() {
        let key = draft.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        AnthropicKeychain.save(key)
        draft = ""
        isFocused = false
        refresh()
    }

    private func remove() {
        AnthropicKeychain.delete()
        draft = ""
        refresh()
    }

    private func mask(_ key: String) -> String {
        guard key.count > 4 else { return String(repeating: "\u{2022}", count: 32) }
        return String(repeating: "\u{2022}", count: 36) + key.suffix(4)
    }

    // MARK: - Custom API actions

    private func saveCustomAPIKey() {
        let key = customDraftKey.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return }
        CustomAPIKeychain.saveAPIKey(key)
        customDraftKey = ""
        customKeyFocused = false
        refresh()
    }

    private func removeCustomAPIKey() {
        CustomAPIKeychain.deleteAPIKey()
        customDraftKey = ""
        refresh()
    }

    private func applyCustomSettings() {
        CustomAPIKeychain.isEnabled = customEnabled
        CustomAPIKeychain.baseURL = customBaseURL.trimmingCharacters(in: .whitespaces)
        CustomAPIKeychain.model = customModel.trimmingCharacters(in: .whitespaces)
    }

    private func testCustomAPI() {
        let base = customBaseURL.trimmingCharacters(in: .whitespaces)
        let key = (CustomAPIKeychain.loadAPIKey() ?? "").isEmpty
            ? customDraftKey.trimmingCharacters(in: .whitespaces)
            : (CustomAPIKeychain.loadAPIKey() ?? "")
        guard !base.isEmpty, !key.isEmpty else {
            customTestStatus = .failure("请先填写地址和 API Key")
            return
        }
        let urlStr = base.hasSuffix("/") ? "\(base)models" : "\(base)/models"
        guard let url = URL(string: urlStr) else {
            customTestStatus = .failure("地址格式无效")
            return
        }
        customTestStatus = .testing
        Task {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            do {
                let (data, resp) = try await URLSession.shared.data(for: req)
                if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    customTestStatus = .failure("HTTP \(http.statusCode): \(body.prefix(80))")
                    return
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["data"] as? [[String: Any]] {
                    customTestStatus = .success("连接成功，共 \(models.count) 个模型")
                } else {
                    customTestStatus = .success("连接成功")
                }
            } catch {
                customTestStatus = .failure(error.localizedDescription)
            }
        }
    }

    // MARK: - MCP server

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.smMd) {
            mcpHeader
            mcpStatusRow
        }
    }

    private var mcpHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("MCP 服务器")
                .font(.system(size: AppTheme.FontSize.md, weight: .medium))
                .foregroundStyle(AppTheme.Text.primaryColor)

            HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                Text("允许 Cursor、Claude Desktop、Claude Code 等外部客户端编辑时间线。")
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: openInstructions) {
                    HStack(spacing: 2) {
                        Text("配置说明")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: AppTheme.FontSize.xs, weight: .semibold))
                    }
                    .font(.system(size: AppTheme.FontSize.sm))
                    .foregroundStyle(AppTheme.Accent.primary)
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
    }

    private var mcpStatusRow: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            HStack(spacing: AppTheme.Spacing.sm) {
                Circle()
                    .fill((appState.mcpService?.isRunning ?? false) ? Color.green : AppTheme.Text.mutedColor)
                    .frame(width: 8, height: 8)

                if appState.mcpService?.isRunning ?? false {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("运行中：")
                            .foregroundStyle(AppTheme.Text.secondaryColor)
                        Text("127.0.0.1:\(String(MCPService.port))")
                            .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                            .foregroundStyle(AppTheme.Text.primaryColor)
                    }
                } else {
                    Text("已停止")
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
            }
            .font(.system(size: AppTheme.FontSize.sm))

            Spacer()

            Toggle(
                "",
                isOn: Binding(
                    get: { (appState.mcpService?.isRunning ?? false) },
                    set: { appState.setMCPEnabled($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.smMd)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .fill(Color.black.opacity(AppTheme.Opacity.muted))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                .strokeBorder(AppTheme.Border.subtleColor, lineWidth: AppTheme.BorderWidth.thin)
        )
    }

    private func openInstructions() {
        HelpWindowController.shared.show(tab: .mcp)
    }
}
