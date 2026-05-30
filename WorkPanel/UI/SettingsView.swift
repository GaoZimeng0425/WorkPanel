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
        VStack(alignment: .leading, spacing: 16) {
            Text("设置").font(.headline)

            Form {
                Section("快捷键") {
                    KeyboardShortcuts.Recorder("唤起捕获面板：", name: .toggleCapture)
                    KeyboardShortcuts.Recorder("唤起看板面板：", name: .toggleBoard)
                    KeyboardShortcuts.Recorder("唤起设置面板：", name: .toggleSettings)
                }

                Section("通用") {
                    Toggle("开机自启动", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do { try LaunchAtLogin.setEnabled(enabled) }
                            catch { launchAtLogin = LaunchAtLogin.isEnabled }
                        }
                    Picker("外观主题", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .onChange(of: appearance) { _, raw in
                        (Appearance(rawValue: raw) ?? .system).apply()
                    }
                    Picker("新任务默认优先级", selection: $defaultPriority) {
                        ForEach(Priority.allCases.reversed(), id: \.rawValue) {
                            Text(Theme.priorityLabel($0)).tag($0.rawValue)
                        }
                    }
                }

                Section("提醒") {
                    Picker("提前提醒", selection: $leadMinutes) {
                        ForEach(leadOptions, id: \.self) { m in
                            Text(m == 0 ? "准时" : "\(m) 分钟前").tag(m)
                        }
                    }
                    Toggle("通知声音", isOn: $sound)
                }
            }

            HStack {
                Spacer()
                Button("完成") { onClose() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius))
        .onKeyPress(.escape) { onClose(); return .handled }
    }
}
