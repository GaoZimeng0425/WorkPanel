import Foundation

/// 一个可命名的 AI 动作模板。`shape` 决定它跑在什么上、输出去哪:
/// - `.singleTask`:跑在单个选中任务上,预览后写入 notes。
/// - `.review`:跑在所有未完成任务上,在复盘透镜里展示。
struct AIPrompt: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var shape: Shape
    var template: String   // 作为 system message 发送

    enum Shape: String, Codable, CaseIterable, Identifiable {
        case singleTask, review
        var id: String { rawValue }
        var label: String {
            switch self {
            case .singleTask: "单任务"
            case .review:     "复盘"
            }
        }
    }
}

/// AIPrompt 的持久化:JSON 编码进 UserDefaults。空时返回两个内置默认 prompt。
enum AIPromptStore {
    /// 内置默认 prompt 用固定 UUID,保证多次 load 的 id 稳定(Picker 选中态不抖)。
    static let defaults: [AIPrompt] = [
        AIPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "梳理拓展",
            shape: .singleTask,
            template: "你是一个任务梳理助手。根据下面这条任务的标题与备注,把它梳理清楚并拓展成可执行的步骤,用 markdown 清单(可含 [ ] 复选框)输出,必要时补充关键注意事项。只输出梳理后的内容,不要寒暄。"
        ),
        AIPrompt(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "复盘总结",
            shape: .review,
            template: "你是一个工作复盘助手。下面是我所有进行中(未完成)的任务。请做一次整体复盘与总结:概述当前在推进的事情、指出重点与风险、给出接下来建议优先处理的几项。用简洁的 markdown 输出。"
        ),
    ]

    static func load() -> [AIPrompt] {
        guard let raw = UserDefaults.standard.string(forKey: AppSettings.Key.aiPrompts),
              let data = raw.data(using: .utf8),
              let prompts = try? JSONDecoder().decode([AIPrompt].self, from: data),
              !prompts.isEmpty
        else { return defaults }
        return prompts
    }

    static func save(_ prompts: [AIPrompt]) {
        guard let data = try? JSONEncoder().encode(prompts),
              let raw = String(data: data, encoding: .utf8) else { return }
        UserDefaults.standard.set(raw, forKey: AppSettings.Key.aiPrompts)
    }
}
