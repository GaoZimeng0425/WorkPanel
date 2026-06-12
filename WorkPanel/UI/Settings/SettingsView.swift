import AppKit
import SwiftUI
import SwiftData
import KeyboardShortcuts
import UniformTypeIdentifiers

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
    @AppStorage(AppSettings.Key.lanSyncEnabled) private var lanSyncEnabled = false
    @AppStorage(AppSettings.Key.lanSyncPairingCode) private var lanSyncPairingCode = ""
    @State private var lanStatus = LANSyncStatus.shared

    @State private var selectedTab: SettingsTab = .shortcuts

    @State private var pendingImport: PendingImport?
    @State private var importIncludesSettings = false

    /// .sheet(item:) 需要 Identifiable 包装。
    private struct PendingImport: Identifiable {
        let id = UUID()
        let doc: SyncDocument
    }

    private let leadOptions = [0, 5, 15, 30]

    /// 左侧 tab。rawValue 仅作 Identifiable 用,不持久化。
    private enum SettingsTab: String, CaseIterable, Identifiable {
        case shortcuts, general, reminder, mcp, ai, lan
        var id: String { rawValue }
        var label: String {
            switch self {
            case .shortcuts: "快捷键"
            case .general:   "通用"
            case .reminder:  "提醒"
            case .mcp:       "AI 接入"
            case .ai:        "AI 助手"
            case .lan:       "局域网同步"
            }
        }
        var icon: String {
            switch self {
            case .shortcuts: "command"
            case .general:   "slider.horizontal.3"
            case .reminder:  "bell"
            case .mcp:       "network"
            case .ai:        "sparkles"
            case .lan:       "wifi"
            }
        }
    }

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

    /// 直接粘贴给 AI Agent 的自然语言提示,让它自行完成 MCP 接入。
    private var mcpAgentPrompt: String {
        """
        请帮我接入一个名为 workpanel 的本地 MCP 服务器(用于管理我的任务和看板)。\
        请根据我正在使用的 AI 工具,用下面的连接信息完成添加:
        - 传输方式 (transport): http
        - 地址 (url): \(mcpURL)
        - 请求头 (headers): Authorization: Bearer \(mcpToken)

        例如在 Claude Code 中可执行:
        \(mcpAddCommand)

        接入后你可以增删改查任务、在看板列间移动任务。任务字段包括:\
        标题 (title)、备注 (notes)、开始日期 (startDate)、截止日期 (deadline)、\
        优先级 (priority)、标签 (tags)、重复规则 (recurrence)、紧急标记 (urgent)、\
        所属看板列 (columnID),以及完成、重开、推迟 (snooze) 等状态操作。\
        list_tasks 支持按完成状态、看板列、标签、优先级、startAfter / dueBefore 过滤。
        """
    }

    private func copy(_ string: String, notice: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        Notice.show(notice)
    }

    private var exportFileName: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "WorkPanel-备份-\(f.string(from: Date())).json"
    }

    private func runExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = exportFileName
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try SyncService.exportData(context: SharedModel.container.mainContext)
            try data.write(to: url)
            Notice.show("已导出")
        } catch {
            Notice.show("导出失败")
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let doc = try SyncService.parse(try Data(contentsOf: url))
            importIncludesSettings = false
            pendingImport = PendingImport(doc: doc)
        } catch {
            Notice.show("导入失败:文件格式无效")
        }
    }

    private func performImport(_ doc: SyncDocument) {
        do {
            let report = try SyncService.merge(doc, into: SharedModel.container.mainContext,
                                               includeSettings: importIncludesSettings)
            if report.settingsApplied {
                AppSettings.appearance.apply()
                NotificationCenter.default.post(name: .mcpSettingsChanged, object: nil)
            }
            Notice.show("导入完成:新增 \(report.totalInserted),更新 \(report.totalUpdated)")
        } catch {
            Notice.show("导入失败:写入存储出错")
        }
    }

    private func importConfirmSheet(_ doc: SyncDocument) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("导入预览")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("将合并 \(doc.tasks.count) 个任务 / \(doc.columns.count) 个看板列 / \(doc.dayPlans.count) 个日计划")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
            Toggle("同时导入设置(含 API Key 等密钥)", isOn: $importIncludesSettings)
                .toggleStyle(.switch)
                .foregroundStyle(Theme.textPrimary)
            HStack {
                Spacer()
                Button("取消") { pendingImport = nil }
                    .buttonStyle(NoirPillButtonStyle())
                Button("导入") {
                    performImport(doc)
                    pendingImport = nil
                }
                .buttonStyle(NoirPillButtonStyle(prominent: true))
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(
            LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                           startPoint: .top, endPoint: .bottom)
        )
        .preferredColorScheme(.dark)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.stroke).frame(width: 1)
            rightPane
        }
        .frame(width: 640, height: 480)
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
        .sheet(item: $pendingImport) { pending in
            importConfirmSheet(pending.doc)
        }
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    // MARK: - 左右分栏

    /// 左侧:标题 + 竖向 tab 列表。
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accentText)
                Text("设置")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 12)

            ForEach(SettingsTab.allCases) { tab in
                tabButton(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .frame(width: 172)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surfaceSubtle)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        let selected = selectedTab == tab
        return Button { selectedTab = tab } label: {
            HStack(spacing: 9) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(tab.label)
                    .font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Theme.surface : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 右侧:当前 tab 内容 + 底部「完成」。
    private var rightPane: some View {
        VStack(spacing: 0) {
            ScrollView {
                content(for: selectedTab)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            HStack {
                Spacer()
                Button("完成") { onClose() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(NoirPillButtonStyle(prominent: true))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func content(for tab: SettingsTab) -> some View {
        switch tab {
        case .shortcuts: shortcutsSection
        case .general:   generalSection
        case .reminder:  reminderSection
        case .mcp:       mcpSection
        case .ai:        aiSection
        case .lan:       lanSection
        }
    }

    // MARK: - 各 tab 内容

    private var shortcutsSection: some View {
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
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 18) {
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
            dataSyncCard
        }
    }

    private var dataSyncCard: some View {
        section("数据同步", systemImage: "arrow.triangle.2.circlepath") {
            row("导出到文件", systemImage: "square.and.arrow.up") {
                Button("导出…") { runExport() }
                    .buttonStyle(NoirPillButtonStyle())
            }
            divider
            row("从文件导入", systemImage: "square.and.arrow.down") {
                Button("导入…") { chooseImport() }
                    .buttonStyle(NoirPillButtonStyle())
            }
        }
    }

    private var reminderSection: some View {
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
    }

    private var mcpSection: some View {
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
                row("发给 AI 自动接入", systemImage: "sparkles") {
                    Button("复制提示词") { copy(mcpAgentPrompt, notice: "已复制 AI 提示词") }
                        .buttonStyle(NoirPillButtonStyle())
                }
                divider
                row("注册命令(Claude Code)", systemImage: "terminal") {
                    Button("复制") { copy(mcpAddCommand, notice: "已复制注册命令") }
                        .buttonStyle(NoirPillButtonStyle())
                }
                divider
                row("配置文件(.mcp.json)", systemImage: "curlybraces") {
                    Button("复制") { copy(mcpJSONConfig, notice: "已复制 JSON 配置") }
                        .buttonStyle(NoirPillButtonStyle())
                }
            }
    }

    private var aiSection: some View {
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
    }

    private var lanSection: some View {
        section("局域网同步", systemImage: "wifi") {
            row("启用", systemImage: "antenna.radiowaves.left.and.right") {
                Toggle("", isOn: $lanSyncEnabled)
                    .labelsHidden().toggleStyle(.switch)
                    .onChange(of: lanSyncEnabled) { _, _ in
                        NotificationCenter.default.post(name: .lanSyncSettingsChanged, object: nil)
                    }
            }
            divider
            row("配对码", systemImage: "key") {
                HStack(spacing: 8) {
                    TextField("两台 Mac 填同一个", text: $lanSyncPairingCode)
                        .labelsHidden().frame(width: 180)
                        .multilineTextAlignment(.trailing)
                        .onSubmit {
                            NotificationCenter.default.post(name: .lanSyncSettingsChanged, object: nil)
                        }
                    Button("生成") {
                        lanSyncPairingCode = String(UUID().uuidString.prefix(8))
                        NotificationCenter.default.post(name: .lanSyncSettingsChanged, object: nil)
                    }
                    .buttonStyle(NoirPillButtonStyle())
                }
            }
            divider
            row("状态", systemImage: "dot.radiowaves.left.and.right") {
                Text(lanStatus.isRunning ? "运行中" : "已停止")
                    .font(.callout).foregroundStyle(Theme.textSecondary)
            }
            divider
            row("已发现设备", systemImage: "laptopcomputer") {
                Text(lanStatus.peerNames.isEmpty ? "无" : lanStatus.peerNames.joined(separator: "、"))
                    .font(.callout).foregroundStyle(Theme.textSecondary)
            }
            divider
            row("上次同步", systemImage: "clock.arrow.2.circlepath") {
                Text(lanStatus.lastSync)
                    .font(.callout).foregroundStyle(Theme.textSecondary)
            }
        }
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
