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
    var body: some Scene {
        MenuBarExtra("WorkPanel", systemImage: "checklist") {
            Text("WorkPanel")   // placeholder, replaced in Task 10
                .padding()
                .modelContainer(SharedModel.container)
        }
        .menuBarExtraStyle(.window)
    }
}
