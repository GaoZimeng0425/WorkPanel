import AppKit
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    let onClose: () -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(AppSettings.Key.appearance) private var appearance = Appearance.system.rawValue
    @AppStorage(AppSettings.Key.defaultPriority) private var defaultPriority = Priority.medium.rawValue
    @AppStorage(AppSettings.Key.reminderLeadMinutes) private var leadMinutes = 0
    @AppStorage(AppSettings.Key.notificationSound) private var sound = true
    @AppStorage(AppSettings.Key.mcpEnabled) private var mcpEnabled = false
    @AppStorage(AppSettings.Key.mcpPort) private var mcpPort = 8787
    @State private var mcpToken = AppSettings.mcpToken
    @AppStorage(AppSettings.Key.aiBaseURL) private var aiBaseURL = ""
    @AppStorage(AppSettings.Key.aiModel) private var aiModel = ""
    @AppStorage(AppSettings.Key.aiAPIKey) private var aiAPIKey = ""

    private let leadOptions = [0, 5, 15, 30]

    private var mcpURL: String { "http://127.0.0.1:\(mcpPort)/mcp" }

    /// 可直接粘贴到终端运行的 Claude Code 注册命令。
    private var mcpAddCommand: String {
        "claude mcp add --transport http workpanel \(mcpURL) --header \"Authorization: Bearer \(mcpToken)\""
    }

    /// mcpServers 风格的 JSON,适合粘贴到 .mcp.json / claude_desktop_config.json。
    private var mcpJSONConfig: String {
        """
        {
          "mcpServers": {
            "workpanel": {
              "type": "http",
              "url": "\(mcpURL)",
              "headers": {
                "Authorization": "Bearer \(mcpToken)"
              }
            }
          }
        }
        """
    }

    private func copy(_ string: String, notice: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        Notice.show(notice)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accentText)
                Text("设置")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            section("快捷键", systemImage: "command") {
                row("捕获面板", systemImage: "square.and.pencil") {
                    KeyboardShortcuts.Recorder("", name: .toggleCapture)
                }
                divider
                row("看板面板", systemImage: "rectangle.split.3x1") {
                    KeyboardShortcuts.Recorder("", name: .toggleBoard)
                }
                divider
                row("设置面板", systemImage: "gearshape") {
                    Text("⌘,").font(.callout).foregroundStyle(Theme.textSecondary)
                }
            }

            section("通用", systemImage: "slider.horizontal.3") {
                row("开机自启动", systemImage: "power") {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do { try LaunchAtLogin.setEnabled(enabled) }
                            catch { launchAtLogin = LaunchAtLogin.isEnabled }
                        }
                }
                divider
                row("外观主题", systemImage: "circle.lefthalf.filled") {
                    Picker("", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: appearance) { _, raw in
                        (Appearance(rawValue: raw) ?? .system).apply()
                    }
                }
                divider
                row("新任务默认优先级", systemImage: "flag") {
                    Picker("", selection: $defaultPriority) {
                        ForEach(Priority.allCases.reversed(), id: \.rawValue) {
                            Text(Theme.priorityLabel($0)).tag($0.rawValue)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            section("提醒", systemImage: "bell") {
                row("提前提醒", systemImage: "clock") {
                    Picker("", selection: $leadMinutes) {
                        ForEach(leadOptions, id: \.self) { m in
                            Text(m == 0 ? "准时" : "\(m) 分钟前").tag(m)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                divider
                row("通知声音", systemImage: "speaker.wave.2") {
                    Toggle("", isOn: $sound).labelsHidden().toggleStyle(.switch)
                }
            }

            section("AI 接入 (MCP)", systemImage: "sparkles") {
                row("启用本地服务", systemImage: "network") {
                    Toggle("", isOn: $mcpEnabled)
                        .labelsHidden().toggleStyle(.switch)
                        .onChange(of: mcpEnabled) { _, _ in
                            NotificationCenter.default.post(name: .mcpSettingsChanged, object: nil)
                        }
                }
                divider
                row("端口", systemImage: "number") {
                    TextField("", value: $mcpPort, format: .number.grouping(.never))
                        .labelsHidden().frame(width: 80)
                        .multilineTextAlignment(.trailing)
                        .onSubmit {
                            if mcpPort < 1 || mcpPort > 65535 { mcpPort = 8787 }
                            NotificationCenter.default.post(name: .mcpSettingsChanged, object: nil)
                        }
                }
                divider
                row("连接地址", systemImage: "link") {
                    Text(mcpURL)
                        .font(.callout.monospaced()).foregroundStyle(Theme.textSecondary)
                        .textSelection(.enabled)
                }
                divider
                row("访问令牌", systemImage: "key") {
                    Button("复制令牌") { copy(mcpToken, notice: "已复制访问令牌") }
                        .buttonStyle(NoirPillButtonStyle())
                }
                divider
                row("一键复制设置", systemImage: "doc.on.doc") {
                    HStack(spacing: 8) {
                        Button("复制命令") { copy(mcpAddCommand, notice: "已复制注册命令") }
                            .buttonStyle(NoirPillButtonStyle())
                        Button("复制 JSON") { copy(mcpJSONConfig, notice: "已复制 JSON 配置") }
                            .buttonStyle(NoirPillButtonStyle())
                    }
                }
            }

            section("AI 助手", systemImage: "sparkles") {
                row("接口地址", systemImage: "link") {
                    TextField("https://api.openai.com/v1", text: $aiBaseURL)
                        .labelsHidden().frame(width: 220)
                        .multilineTextAlignment(.trailing)
                }
                divider
                row("模型名称", systemImage: "cpu") {
                    TextField("gpt-4o-mini", text: $aiModel)
                        .labelsHidden().frame(width: 220)
                        .multilineTextAlignment(.trailing)
                }
                divider
                row("API Key", systemImage: "key") {
                    SecureField("sk-…", text: $aiAPIKey)
                        .labelsHidden().frame(width: 220)
                        .multilineTextAlignment(.trailing)
                }
                divider
                VStack(alignment: .leading, spacing: 8) {
                    Label("提示词", systemImage: "text.bubble")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Theme.textPrimary)
                    AIPromptListView()
                }
            }

            HStack {
                Spacer()
                Button("完成") { onClose() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(NoirPillButtonStyle(prominent: true))
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(
            LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                           startPoint: .top, endPoint: .bottom)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .preferredColorScheme(.dark)
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    // MARK: - 分组卡片与行

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(height: 1)
    }

    /// 分组:小标题 + 圆角卡片容器。
    @ViewBuilder
    private func section<Content: View>(_ title: String, systemImage: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            VStack(spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.surfaceSubtle,
                            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .stroke(Theme.strokeStrong, lineWidth: 0.7)
                )
        }
    }

    /// 单行:左侧图标+标题,右侧控件。
    private func row<Control: View>(_ title: String, systemImage: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            control()
        }
    }
}
