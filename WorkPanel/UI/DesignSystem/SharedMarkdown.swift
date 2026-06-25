import SwiftUI
import AppKit
import MarkdownEngine

/// 共享的 MarkdownEngine 编辑器配置(noir 调色 + 收紧字号/内边距)。
/// 由 TaskEditorView 与 AllTasksEditorView 共用,保证两处着色一致。
enum SharedMarkdown {
    @MainActor static var editorConfig: MarkdownEditorConfiguration {
        let orange = NSColor(Theme.accent)
        var theme = MarkdownEditorTheme.default
        theme.bodyText = NSColor(Theme.textPrimary)
        theme.mutedText = orange
        theme.disabledText = NSColor(Theme.textMuted)
        theme.headingMarker = orange
        theme.link = orange
        theme.strikethroughColor = NSColor(Theme.textTertiary)

        var config = MarkdownEditorConfiguration.default
        config.theme = theme
        config.textInsets = TextInsets(horizontal: 14, vertical: 12)
        config.headings.fontMultipliers = [1.5, 1.3, 1.15, 1.0, 0.9, 0.8]
        config.overscroll = OverscrollPolicy(percent: 0.1, maxPoints: 40, minPoints: 0)
        config.lists.autoClosePairsEnabled = false
        config.lists.indentPerLevel = 0
        return config
    }
}
