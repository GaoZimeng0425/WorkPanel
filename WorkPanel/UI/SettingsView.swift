import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置").font(.headline)

            Form {
                KeyboardShortcuts.Recorder("唤起捕获面板：", name: .toggleCapture)
                KeyboardShortcuts.Recorder("唤起看板面板：", name: .toggleBoard)
                Toggle("开机自启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do { try LaunchAtLogin.setEnabled(enabled) }
                        catch { launchAtLogin = LaunchAtLogin.isEnabled }
                    }
            }

            HStack {
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}
