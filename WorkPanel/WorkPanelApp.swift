import SwiftUI
import SwiftData

enum SharedModel {
    @MainActor static let container: ModelContainer = {
        let schema = Schema([TodoTask.self, BoardColumn.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()
}

@main
struct WorkPanelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("WorkPanel", systemImage: "checklist") {
            TaskListView()
                .modelContainer(SharedModel.container)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panel = PanelController()
    private let board = BoardPanelController()
    private let settings = SettingsPanelController()
    private let scheduler = ReminderScheduler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        AppSettings.appearance.apply()
        HotkeyManager.register { [weak self] in self?.toggleCapture() }
        HotkeyManager.registerBoard { [weak self] in self?.toggleBoard() }
        HotkeyManager.registerSettings { [weak self] in self?.toggleSettings() }
        NotificationCenter.default.addObserver(forName: .openSettings, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.toggleSettings() }
        }
        Task { _ = await scheduler.requestAuthorization() }
    }

    private func toggleCapture() {
        if panel.isVisible { panel.hide(); return }
        let context = ModelContext(SharedModel.container)
        let store = TodoStore(context: context)
        panel.show {
            CaptureView(
                onSave: { [weak self] parsed, notes in
                    let task = store.add(parsed, notes: notes)
                    task.columnID = BoardStore(context: context).firstColumn?.id
                    try? context.save()
                    let scheduler = self?.scheduler
                    Task { await scheduler?.schedule(for: task) }
                    self?.panel.hide()
                },
                onCancel: { [weak self] in self?.panel.hide() }
            )
        }
    }

    private func toggleBoard() {
        if board.isVisible { board.hide(); return }
        board.show {
            BoardView(onClose: { [weak self] in self?.board.hide() })
                .modelContainer(SharedModel.container)
        }
    }

    private func toggleSettings() {
        settings.toggle {
            SettingsView(onClose: { [weak self] in self?.settings.hide() })
        }
    }
}
