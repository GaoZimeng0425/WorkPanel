import Foundation
import Testing
@testable import WorkPanel

@MainActor
struct ColumnSortOptionTests {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func manual按boardOrder升序() {
        let tasks = [
            TodoTask(title: "乙", boardOrder: 2),
            TodoTask(title: "丙", boardOrder: 3),
            TodoTask(title: "甲", boardOrder: 1),
        ]
        #expect(ColumnSortOption.manual.sorted(tasks).map(\.title) == ["甲", "乙", "丙"])
    }

    @Test func priority高在前平局按boardOrder() {
        let tasks = [
            TodoTask(title: "低", priority: .low, boardOrder: 0),
            TodoTask(title: "高乙", priority: .high, boardOrder: 2),
            TodoTask(title: "中", priority: .medium, boardOrder: 1),
            TodoTask(title: "高甲", priority: .high, boardOrder: 3),
        ]
        #expect(ColumnSortOption.priority.sorted(tasks).map(\.title) == ["高乙", "高甲", "中", "低"])
    }

    @Test func deadline近的在前无截止殿后平局按boardOrder() {
        let tasks = [
            TodoTask(title: "无乙", boardOrder: 5),
            TodoTask(title: "远", deadline: base.addingTimeInterval(7200), boardOrder: 0),
            TodoTask(title: "无甲", boardOrder: 4),
            TodoTask(title: "近", deadline: base.addingTimeInterval(3600), boardOrder: 1),
            TodoTask(title: "同远乙", deadline: base.addingTimeInterval(7200), boardOrder: 3),
            TodoTask(title: "同远甲", deadline: base.addingTimeInterval(7200), boardOrder: 2),
        ]
        #expect(ColumnSortOption.deadline.sorted(tasks).map(\.title)
                == ["近", "远", "同远甲", "同远乙", "无甲", "无乙"])
    }

    @Test func createdAt新的在前平局按boardOrder() {
        let tasks = [
            TodoTask(title: "旧", createdAt: base, boardOrder: 0),
            TodoTask(title: "新乙", createdAt: base.addingTimeInterval(600), boardOrder: 6),
            TodoTask(title: "新甲", createdAt: base.addingTimeInterval(600), boardOrder: 5),
        ]
        #expect(ColumnSortOption.createdAt.sorted(tasks).map(\.title) == ["新甲", "新乙", "旧"])
    }

    @Test func title按localizedStandard升序平局按boardOrder() {
        let tasks = [
            TodoTask(title: "任务10", boardOrder: 0),
            TodoTask(title: "任务2", boardOrder: 1),
            TodoTask(title: "同", boardOrder: 4),
            TodoTask(title: "同", boardOrder: 3),
            TodoTask(title: "任务1", boardOrder: 2),
        ]
        // localizedStandard 按数值感知排序:"任务2" < "任务10";同名标题交给 boardOrder 决胜
        let sorted = ColumnSortOption.title.sorted(tasks)
        #expect(sorted.map(\.title) == ["任务1", "任务2", "任务10", "同", "同"])
        #expect(sorted.map(\.boardOrder) == [2, 1, 0, 3, 4])   // 同名对按 boardOrder 分先后
    }

    @Test func fromRaw为nil或未知字符串时回退manual() {
        #expect(ColumnSortOption.from(raw: nil) == .manual)
        #expect(ColumnSortOption.from(raw: "bogus") == .manual)
        #expect(ColumnSortOption.from(raw: "priority") == .priority)
    }

    // MARK: - 方向支持(sorted(_:descending:) 与 preferredDescending)

    @Test func priority升序低到高平局按boardOrder() {
        let tasks = [
            TodoTask(title: "低", priority: .low, boardOrder: 0),
            TodoTask(title: "高乙", priority: .high, boardOrder: 2),
            TodoTask(title: "中", priority: .medium, boardOrder: 1),
            TodoTask(title: "高甲", priority: .high, boardOrder: 3),
        ]
        #expect(ColumnSortOption.priority.sorted(tasks, descending: false).map(\.title)
                == ["低", "中", "高乙", "高甲"])
    }

    @Test func priority降序高到低平局按boardOrder() {
        let tasks = [
            TodoTask(title: "低", priority: .low, boardOrder: 0),
            TodoTask(title: "高乙", priority: .high, boardOrder: 2),
            TodoTask(title: "中", priority: .medium, boardOrder: 1),
            TodoTask(title: "高甲", priority: .high, boardOrder: 3),
        ]
        #expect(ColumnSortOption.priority.sorted(tasks, descending: true).map(\.title)
                == ["高乙", "高甲", "中", "低"])
    }

    @Test func deadline升序近到远无截止殿后() {
        let tasks = [
            TodoTask(title: "无乙", boardOrder: 5),
            TodoTask(title: "中", deadline: base.addingTimeInterval(5400), boardOrder: 9),
            TodoTask(title: "远", deadline: base.addingTimeInterval(7200), boardOrder: 0),
            TodoTask(title: "无甲", boardOrder: 4),
            TodoTask(title: "近", deadline: base.addingTimeInterval(3600), boardOrder: 1),
            TodoTask(title: "同远甲", deadline: base.addingTimeInterval(7200), boardOrder: 7),
            TodoTask(title: "同远乙", deadline: base.addingTimeInterval(7200), boardOrder: 6),
        ]
        #expect(ColumnSortOption.deadline.sorted(tasks, descending: false).map(\.title)
                == ["近", "中", "远", "同远乙", "同远甲", "无甲", "无乙"])
    }

    @Test func deadline降序远到近无截止仍殿后() {
        let tasks = [
            TodoTask(title: "无乙", boardOrder: 5),
            TodoTask(title: "中", deadline: base.addingTimeInterval(5400), boardOrder: 9),
            TodoTask(title: "远", deadline: base.addingTimeInterval(7200), boardOrder: 0),
            TodoTask(title: "无甲", boardOrder: 4),
            TodoTask(title: "近", deadline: base.addingTimeInterval(3600), boardOrder: 1),
            TodoTask(title: "同远甲", deadline: base.addingTimeInterval(7200), boardOrder: 7),
            TodoTask(title: "同远乙", deadline: base.addingTimeInterval(7200), boardOrder: 6),
        ]
        // 降序仅翻转主键:同远平局组仍按 boardOrder(远、同远乙、同远甲),无截止两件殿后不变
        #expect(ColumnSortOption.deadline.sorted(tasks, descending: true).map(\.title)
                == ["远", "同远乙", "同远甲", "中", "近", "无甲", "无乙"])
    }

    @Test func createdAt升序旧到新平局按boardOrder() {
        let tasks = [
            TodoTask(title: "旧", createdAt: base, boardOrder: 0),
            TodoTask(title: "新乙", createdAt: base.addingTimeInterval(600), boardOrder: 6),
            TodoTask(title: "同甲", createdAt: base.addingTimeInterval(300), boardOrder: 8),
            TodoTask(title: "新甲", createdAt: base.addingTimeInterval(600), boardOrder: 5),
            TodoTask(title: "同乙", createdAt: base.addingTimeInterval(300), boardOrder: 7),
        ]
        #expect(ColumnSortOption.createdAt.sorted(tasks, descending: false).map(\.title)
                == ["旧", "同乙", "同甲", "新甲", "新乙"])   // 同秒平局按 boardOrder:7(同乙)在 8(同甲)前
    }

    @Test func createdAt降序新到旧平局按boardOrder() {
        let tasks = [
            TodoTask(title: "旧", createdAt: base, boardOrder: 0),
            TodoTask(title: "新乙", createdAt: base.addingTimeInterval(600), boardOrder: 6),
            TodoTask(title: "同甲", createdAt: base.addingTimeInterval(300), boardOrder: 8),
            TodoTask(title: "新甲", createdAt: base.addingTimeInterval(600), boardOrder: 5),
            TodoTask(title: "同乙", createdAt: base.addingTimeInterval(300), boardOrder: 7),
        ]
        #expect(ColumnSortOption.createdAt.sorted(tasks, descending: true).map(\.title)
                == ["新甲", "新乙", "同乙", "同甲", "旧"])   // 平局组仍按 boardOrder 升序,不随方向翻转
    }

    @Test func title升序AZ平局按boardOrder() {
        let tasks = [
            TodoTask(title: "任务10", boardOrder: 0),
            TodoTask(title: "任务2", boardOrder: 1),
            TodoTask(title: "同", boardOrder: 4),
            TodoTask(title: "同", boardOrder: 3),
            TodoTask(title: "任务1", boardOrder: 2),
        ]
        let sorted = ColumnSortOption.title.sorted(tasks, descending: false)
        #expect(sorted.map(\.title) == ["任务1", "任务2", "任务10", "同", "同"])
        #expect(sorted.map(\.boardOrder) == [2, 1, 0, 3, 4])   // 同名对按 boardOrder 分先后
    }

    @Test func title降序ZA平局按boardOrder() {
        let tasks = [
            TodoTask(title: "任务10", boardOrder: 0),
            TodoTask(title: "任务2", boardOrder: 1),
            TodoTask(title: "同", boardOrder: 4),
            TodoTask(title: "同", boardOrder: 3),
            TodoTask(title: "任务1", boardOrder: 2),
        ]
        let sorted = ColumnSortOption.title.sorted(tasks, descending: true)
        #expect(sorted.map(\.title) == ["同", "同", "任务10", "任务2", "任务1"])
        #expect(sorted.map(\.boardOrder) == [3, 4, 0, 1, 2])   // 平局组不随方向翻转
    }

    @Test func preferredDescending各规则常用方向() {
        // v1 现行为:优先级高在前、创建新在前(降序);截止近在前、标题 A→Z(升序)
        #expect(ColumnSortOption.priority.preferredDescending == true)
        #expect(ColumnSortOption.deadline.preferredDescending == false)
        #expect(ColumnSortOption.createdAt.preferredDescending == true)
        #expect(ColumnSortOption.title.preferredDescending == false)
    }
}
