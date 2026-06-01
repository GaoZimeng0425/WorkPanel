import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct PlanStoreTests {
    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, DayPlan.self, configurations: config)
        return ModelContext(container)
    }

    @Test func dayPlanPersists() throws {
        let context = try makeContext()
        let plan = DayPlan(day: Date(timeIntervalSinceReferenceDate: 0), committedTaskIDs: [UUID()])
        context.insert(plan)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<DayPlan>()).count == 1)
    }
}
