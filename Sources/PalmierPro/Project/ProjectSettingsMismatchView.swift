import SwiftUI

struct ProjectSettingsMismatchView: View {
    @Environment(EditorViewModel.self) var editor
    let mismatch: EditorViewModel.SettingsMismatch

    var body: some View {
        VStack(spacing: AppTheme.Spacing.xl) {
            Text("片段设置不匹配")
                .font(.system(size: AppTheme.FontSize.xl, weight: .semibold))
                .foregroundStyle(AppTheme.Text.primaryColor)

            Text("所添加的片段与当前项目的设置不同。")
                .font(.system(size: AppTheme.FontSize.sm))
                .foregroundStyle(AppTheme.Text.secondaryColor)
                .multilineTextAlignment(.center)

            Grid(alignment: .leading, horizontalSpacing: AppTheme.Spacing.xl, verticalSpacing: AppTheme.Spacing.sm) {
                GridRow {
                    Text("")
                    Text("项目")
                        .font(.system(size: AppTheme.FontSize.xs, weight: .semibold))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                    Text("Clip")
                        .font(.system(size: AppTheme.FontSize.xs, weight: .semibold))
                        .foregroundStyle(AppTheme.Text.tertiaryColor)
                }
                GridRow {
                    Text("FPS")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                    Text("\(editor.timeline.fps)")
                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                    Text("\(mismatch.clipFPS)")
                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                        .foregroundStyle(mismatch.clipFPS != editor.timeline.fps ? .orange : AppTheme.Text.primaryColor)
                }
                GridRow {
                    Text("Resolution")
                        .font(.system(size: AppTheme.FontSize.sm))
                        .foregroundStyle(AppTheme.Text.secondaryColor)
                    Text("\(editor.timeline.width) x \(editor.timeline.height)")
                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                        .foregroundStyle(AppTheme.Text.primaryColor)
                    Text("\(mismatch.clipWidth) x \(mismatch.clipHeight)")
                        .font(.system(size: AppTheme.FontSize.sm, design: .monospaced))
                        .foregroundStyle(resolutionMismatch ? .orange : AppTheme.Text.primaryColor)
                }
            }

            HStack(spacing: AppTheme.Spacing.md) {
                Button("Keep Current") {
                    dismiss()
                }
                .buttonStyle(.capsule(.secondary, size: .regular))
                .controlSize(.regular)

                Button("Change to Match") {
                    editor.applyTimelineSettings(
                        fps: mismatch.clipFPS,
                        width: mismatch.clipWidth,
                        height: mismatch.clipHeight
                    )
                    dismiss()
                }
                .buttonStyle(.capsule(.prominent, size: .regular))
                .controlSize(.regular)
            }
        }
        .padding(AppTheme.Spacing.xl + AppTheme.Spacing.md)
        .frame(width: 360)
    }

    private func dismiss() {
        editor.pendingSettingsContinuation?()
        editor.pendingSettingsContinuation = nil
        editor.pendingSettingsMismatch = nil
    }

    private var resolutionMismatch: Bool {
        mismatch.clipWidth != editor.timeline.width || mismatch.clipHeight != editor.timeline.height
    }
}
