import Testing
import Foundation
import SwiftData
@testable import WorkPanel

@MainActor
struct BoardColumnSortTests {
    private func makeStore() throws -> BoardStore {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: TodoTask.self, BoardColumn.self, configurations: config)
        return BoardStore(context: ModelContext(container))
    }

    @Test func sortRawNil与未知字符串都回退manual() {
        let col = BoardColumn(name: "待办", order: 0)
        col.sortRaw = nil
        #expect(col.sort == .manual)
        col.sortRaw = "不存在的选项"
        #expect(col.sort == .manual)
    }

    @Test func setSort写入非手动选项后sort正确切回manual时sortRaw为nil() throws {
        let store = try makeStore()
        let col = store.addColumn(name: "待办")

        store.setSort(col, to: .priority)
        #expect(col.sortRaw == ColumnSortOption.priority.rawValue)
        #expect(col.sort == .priority)

        store.setSort(col, to: .manual)
        #expect(col.sortRaw == nil)
        #expect(col.sort == .manual)
    }

    @Test func syncColumnDTO往返() throws {
        let col = BoardColumn(name: "开发中", order: 1)
        col.sortRaw = ColumnSortOption.deadline.rawValue
        let dto = SyncColumnDTO(col)
        let back = try SyncDocument.decoder.decode(
            SyncColumnDTO.self, from: try SyncDocument.encoder.encode(dto))
        #expect(back.sortRaw == col.sortRaw)

        let restored = BoardColumn(name: "占位", order: 0)
        back.apply(to: restored)
        #expect(restored.sortRaw == col.sortRaw)
    }

    @Test func 旧格式文档缺sortRaw键可解码() throws {
        let json = #"{"id":"12345678-1234-1234-1234-123456789abc","name":"计划中","order":0,"modifiedAt":"2026-11-12T10:00:00Z"}"#
        let dto = try SyncDocument.decoder.decode(SyncColumnDTO.self, from: Data(json.utf8))
        #expect(dto.name == "计划中")
        #expect(dto.sortRaw == nil)
    }

    // MARK: - Task 2 方向持久化

    @Test func setSort各依据方向为常用方向切手动时方向清false() throws {
        let store = try makeStore()
        let col = store.addColumn(name: "待办")
        for option in ColumnSortOption.allCases where option != .manual {
            store.setSort(col, to: option)
            #expect(col.sortRaw == option.rawValue)
            #expect(col.sortDescending == option.preferredDescending)
        }
        store.setSort(col, to: .priority)   // 方向 true,验证切手动确实清掉
        store.setSort(col, to: .manual)
        #expect(col.sortRaw == nil)
        #expect(col.sortDescending == false)
    }

    @Test func toggleSortDirection翻转方向且手动时noOp() throws {
        let store = try makeStore()
        let col = store.addColumn(name: "待办")
        store.setSort(col, to: .deadline)
        #expect(col.sortDescending == false)
        store.toggleSortDirection(col)
        #expect(col.sortDescending == true)
        store.toggleSortDirection(col)
        #expect(col.sortDescending == false)

        store.setSort(col, to: .manual)
        store.toggleSortDirection(col)
        #expect(col.sortRaw == nil)
        #expect(col.sortDescending == false)
    }

    @Test func clearSort彻底清空排序设置() throws {
        let store = try makeStore()
        let col = store.addColumn(name: "待办")
        store.setSort(col, to: .priority)
        store.clearSort(col)
        #expect(col.sortRaw == nil)
        #expect(col.sortDescending == false)
        #expect(col.sort == .manual)
    }

    @Test func syncColumnDTO往返携带排序方向true与false() throws {
        for direction in [true, false] {
            let col = BoardColumn(name: "开发中", order: 1)
            col.sortRaw = ColumnSortOption.priority.rawValue
            col.sortDescending = direction
            let dto = SyncColumnDTO(col)
            #expect(dto.sortDescending == direction)
            let back = try SyncDocument.decoder.decode(
                SyncColumnDTO.self, from: try SyncDocument.encoder.encode(dto))
            #expect(back.sortDescending == direction)
            let restored = BoardColumn(name: "占位", order: 0)
            back.apply(to: restored)
            #expect(restored.sortDescending == direction)
        }
    }

    @Test func v1旧JSON有sortRaw无sortDescending解码nil且apply落false() throws {
        let json = #"{"id":"12345678-1234-1234-1234-123456789abc","name":"计划中","order":0,"sortRaw":"priority","modifiedAt":"2026-11-12T10:00:00Z"}"#
        let dto = try SyncDocument.decoder.decode(SyncColumnDTO.self, from: Data(json.utf8))
        #expect(dto.sortRaw == "priority")
        #expect(dto.sortDescending == nil)
        let restored = BoardColumn(name: "占位", order: 0)
        dto.apply(to: restored)
        #expect(restored.sortRaw == "priority")
        #expect(restored.sortDescending == false)
    }
}
