import SwiftUI

struct StoragePane: View {
    @State private var cacheBytes: Int64 = 0
    @State private var isClearing = false
    @State private var indexBytes: Int64 = 0
    @State private var modelBytes: Int64 = 0
    @State private var searchEnabled = SearchIndexConfig.enabled

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("缓存")
                        .font(AppTheme.Typography.ui(size: AppTheme.FontSize.md))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                    Text("已保存的播放预览、波形和缩略图，可安全清除，会在需要时自动重建。")
                        .font(AppTheme.Typography.ui(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: AppTheme.Spacing.sm) {
                        Text(displayPath)
                            .font(AppTheme.Typography.mono(size: AppTheme.FontSize.xs).monospaced())
                            .foregroundStyle(AppTheme.Text.tertiaryColor)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(formattedSize)
                            .font(AppTheme.Typography.mono(size: AppTheme.FontSize.xs).monospacedDigit())
                            .foregroundStyle(AppTheme.Text.secondaryColor)
                    }
                    .padding(.top, AppTheme.Spacing.xs)
                }

                Spacer(minLength: AppTheme.Spacing.lg)

                Button("Clear cache") {
                    clear()
                }
                .controlSize(.small)
                .disabled(isClearing || cacheBytes == 0)
            }

            Divider()
                .overlay(AppTheme.Border.subtleColor)

            searchIndexSection
        }
        .task { await refresh() }
    }

    private var searchIndexSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("媒体搜索")
                        .font(AppTheme.Typography.ui(size: AppTheme.FontSize.md))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                    Text("导入时建立索引以支持搜索，在本地运行。")
                        .font(AppTheme.Typography.ui(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: AppTheme.Spacing.lg)
                Toggle("", isOn: $searchEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .onChange(of: searchEnabled) { _, newValue in
                        VisualModelLoader.shared.setEnabled(newValue)
                    }
            }

            HStack(spacing: AppTheme.Spacing.sm) {
                Text("索引")
                    .font(AppTheme.Typography.ui(size: AppTheme.FontSize.xs))
                    .foregroundStyle(AppTheme.Text.tertiaryColor)
                Text(ByteCountFormatter.string(fromByteCount: indexBytes, countStyle: .file))
                    .font(AppTheme.Typography.mono(size: AppTheme.FontSize.xs).monospacedDigit())
                    .foregroundStyle(AppTheme.Text.secondaryColor)
                Button("Clear index") { clearIndex() }
                    .controlSize(.small)
                    .disabled(indexBytes == 0)
            }
            .padding(.top, AppTheme.Spacing.xs)

            if modelBytes > 0 {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Text("模型")
                        .font(AppTheme.Typography.ui(size: AppTheme.FontSize.xs))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                    Text("\(SearchIndexConfig.manifest.model) · \(ByteCountFormatter.string(fromByteCount: modelBytes, countStyle: .file))")
                        .font(AppTheme.Typography.mono(size: AppTheme.FontSize.xs).monospacedDigit())
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                    Button("Remove model") { removeModel() }
                        .controlSize(.small)
                }
            }
        }
    }

    private nonisolated static let caches = [ImageVideoGenerator.cache, MediaVisualCache.diskCache]

    private var displayPath: String {
        DiskCache.rootDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private var formattedSize: String {
        if isClearing { return "Clearing…" }
        return ByteCountFormatter.string(fromByteCount: cacheBytes, countStyle: .file)
    }

    private func clear() {
        isClearing = true
        Task.detached {
            for cache in Self.caches { cache.clear() }
            await MainActor.run { isClearing = false }
            await refresh()
        }
    }

    private func clearIndex() {
        Task {
            await SearchIndexCoordinator.clearIndexGlobally()
            await refresh()
        }
    }

    private func removeModel() {
        Task {
            await VisualModelLoader.shared.remove()
            await refresh()
        }
    }

    private func refresh() async {
        let sizes = await Task.detached {
            (
                cache: Self.caches.reduce(0) { $0 + $1.size() },
                index: DiskCache.bytes(at: EmbeddingStore.directory),
                model: DiskCache.bytes(at: ModelDownloader.modelsDir)
            )
        }.value
        cacheBytes = sizes.cache
        indexBytes = sizes.index
        modelBytes = sizes.model
    }
}
