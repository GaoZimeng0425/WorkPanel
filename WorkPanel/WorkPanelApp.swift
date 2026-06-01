import SwiftUI
import SwiftData

enum SharedModel {
    /// UI 测试启动参数:用内存库 + 注入确定性数据,并自动打开看板,以便 XCUITest 可达。
    @MainActor static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest")
    }

    @MainActor static let container: ModelContainer = {
        let schema = Schema([TodoTask.self, BoardColumn.self, DayPlan.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            if isUITesting { seedUITestData(into: container.mainContext) }
            return container
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// 三列 + 计划中列里 任务A/B/C,供拖拽 UI 测试使用。
    @MainActor private static func seedUITestData(into context: ModelContext) {
        let columns = ["计划中", "开发中", "测试中"].enumerated().map {
            BoardColumn(name: $1, order: $0)
        }
        columns.forEach { context.insert($0) }
        for (i, title) in ["任务A", "任务B", "任务C"].enumerated() {
            let task = TodoTask(title: title)
            task.columnID = columns[0].id
            task.boardOrder = i
            context.insert(task)
        }
        try? context.save()
    }
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
        NotificationCenter.default.addObserver(forName: .openSettings, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.toggleSettings() }
        }
        NotificationCenter.default.addObserver(forName: .openTaskEditor, object: nil, queue: .main) { [weak self] note in
            guard let mode = note.object as? TaskEditorView.Mode else { return }
            MainActor.assumeIsolated { self?.showEditor(mode) }
        }
        Task { _ = await scheduler.requestAuthorization() }

        if SharedModel.isUITesting {
            NSApp.activate(ignoringOtherApps: true)
            toggleBoard()
        }
    }

    private func toggleCapture() {
        if panel.isVisible { panel.hide(); return }
        showEditor(.create(columnID: nil))
    }

    private func showEditor(_ mode: TaskEditorView.Mode) {
        panel.show {
            TaskEditorView(mode: mode, onClose: { [weak self] in self?.panel.hide() })
                .modelContainer(SharedModel.container)
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
