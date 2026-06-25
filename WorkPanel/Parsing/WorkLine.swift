import Foundation

/// 全量编辑器的行解析:仅识别 `!高/!中/!低` 优先级与 `#标签`,其余 token 作为标题字面量。
/// 与 InputParser 不同——本视图不解析时间/重复,故时间词留在标题里。纯函数,便于测试。
struct WorkLine {
    struct Parsed: Equatable, Sendable {
        nonisolated var title: String = ""
        nonisolated var priority: Priority? = nil
        nonisolated var tags: [String] = []
    }

    nonisolated private static let priorityMap: [String: Priority] = [
        "!高": .high, "!中": .medium, "!低": .low,
    ]

    nonisolated static func parse(_ text: String) -> Parsed {
        var result = Parsed()
        var titleWords: [String] = []
        let tokens = text
            .split(whereSeparator: { $0 == " " || $0 == "\u{3000}" })
            .map(String.init)
        for token in tokens {
            if let p = priorityMap[token] {
                result.priority = p
            } else if token.hasPrefix("#"), token.count > 1 {
                result.tags.append(String(token.dropFirst()))
            } else {
                titleWords.append(token)
            }
        }
        result.title = titleWords.joined(separator: " ")
        return result
    }
}
