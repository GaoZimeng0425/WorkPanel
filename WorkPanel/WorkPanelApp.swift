import SwiftUI
import SwiftData

enum SharedModel {
    @MainActor static let container: ModelContainer = {
        let schema = Schema([TodoTask.self])
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
    private let scheduler = ReminderScheduler()

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyManager.register { [weak self] in self?.toggleCapture() }
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
                    try? context.save()
                    let scheduler = self?.scheduler
                    Task { await scheduler?.schedule(for: task) }
                    self?.panel.hide()
                },
                onCancel: { [weak self] in self?.panel.hide() }
            )
        }
    }
}
