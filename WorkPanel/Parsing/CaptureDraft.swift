import Foundation

/// 把捕获编辑器整段文本拆成「第一行(标题 + token)」与「其余行(markdown 备注)」,
/// 并以 base 为基准合并解析结果(缺省即保留)。纯函数,便于测试。
enum CaptureDraft {
    nonisolated static func resolve(text: String,
                        base: ParsedInput,
                        now: Date,
                        calendar: Calendar = .current) -> (fields: ParsedInput, notes: String) {
        let parts = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let firstLine = parts.first.map(String.init) ?? ""
        let body = parts.count > 1 ? String(parts[1]) : ""

        let parsed = InputParser(calendar: calendar)
            .parse(firstLine, now: now, defaultPriority: base.priority)

        var fields = ParsedInput()
        fields.title = parsed.title
        fields.priority = parsed.priority                                  // parse 以 base.priority 为默认
        fields.deadline = parsed.deadline ?? base.deadline                 // 缺省即保留
        fields.tags = parsed.tags.isEmpty ? base.tags : parsed.tags        // 缺省即保留
        fields.recurrence = parsed.recurrence ?? base.recurrence           // 缺省即保留
        fields.urgencyOverride = parsed.urgencyOverride ?? base.urgencyOverride   // 缺省即保留
        return (fields, body)
    }

    /// 控件为 priority/tags 的唯一来源:用捕获面板控件值覆盖解析结果。
    /// deadline/recurrence/urgencyOverride 仍来自第一行 token,原样保留。
    nonisolated static func applyControls(to fields: ParsedInput,
                                          priority: Priority,
                                          tags: [String]) -> ParsedInput {
        var out = fields
        out.priority = priority
        out.tags = tags
        return out
    }
}
