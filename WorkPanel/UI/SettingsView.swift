import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    let onClose: () -> Void

    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(AppSettings.Key.appearance) private var appearance = Appearance.system.rawValue
    @AppStorage(AppSettings.Key.defaultPriority) private var defaultPriority = Priority.medium.rawValue
    @AppStorage(AppSettings.Key.reminderLeadMinutes) private var leadMinutes = 0
    @AppStorage(AppSettings.Key.notificationSound) private var sound = true

    private let leadOptions = [0, 5, 15, 30]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 9) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("设置").font(.title2.weight(.bold))
                Spacer()
            }

            section("快捷键", systemImage: "command") {
                row("捕获面板", systemImage: "square.and.pencil") {
                    KeyboardShortcuts.Recorder("", name: .toggleCapture)
                }
                Divider()
                row("看板面板", systemImage: "rectangle.split.3x1") {
                    KeyboardShortcuts.Recorder("", name: .toggleBoard)
                }
                Divider()
                row("设置面板", systemImage: "gearshape") {
                    Text("⌘,").font(.callout).foregroundStyle(.secondary)
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
                Divider()
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
                Divider()
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
                Divider()
                row("通知声音", systemImage: "speaker.wave.2") {
                    Toggle("", isOn: $sound).labelsHidden().toggleStyle(.switch)
                }
            }

            HStack {
                Spacer()
                Button("完成") { onClose() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
        .onKeyPress(.escape) { onClose(); return .handled }
    }

    // MARK: - 分组卡片与行

    /// 分组:小标题 + 圆角卡片容器。
    @ViewBuilder
    private func section<Content: View>(_ title: String, systemImage: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 10) { content() }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.55),
                            in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }

    /// 单行:左侧图标+标题,右侧控件。
    private func row<Control: View>(_ title: String, systemImage: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
            Spacer()
            control()
        }
    }
}
