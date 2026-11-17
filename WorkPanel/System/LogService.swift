import Foundation
import os

/// 轻量日志门面:控制台走 os.Logger(统一日志系统),并落一份纯文本到 ~/.WorkPanel/logs 便于排查。
/// 形态参考 NemoNotch 的 LogService(静态 debug/info/warn/error + category),但不引入第三方依赖。
enum LogService {
    nonisolated private static let subsystem = Bundle.main.bundleIdentifier ?? "WorkPanel"

    nonisolated(unsafe) private static var loggers: [String: Logger] = [:]
    nonisolated private static let lock = NSLock()

    nonisolated private static let fileURL: URL? = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".WorkPanel/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("workpanel.log")
    }()

    nonisolated private static func logger(_ category: String) -> Logger {
        lock.lock(); defer { lock.unlock() }
        if let existing = loggers[category] { return existing }
        let made = Logger(subsystem: subsystem, category: category)
        loggers[category] = made
        return made
    }

    /// 缓存的 formatter:DateFormatter 构造开销高,且只在 lock 内使用(它非线程安全)。
    nonisolated private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// 单文件上限(字节);超出即轮转。常驻菜单栏应用只追加不清理会无界增长。
    nonisolated static let maxLogBytes = 1_000_000

    /// 超限轮转:workpanel.log → workpanel.log.old(旧 .old 直接覆盖丢弃),保留最近一份即可。
    nonisolated static func rotateIfNeeded(at url: URL, maxBytes: Int = maxLogBytes) {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
              size.intValue >= maxBytes else { return }
        let old = url.appendingPathExtension("old")
        try? fm.removeItem(at: old)
        try? fm.moveItem(at: url, to: old)
    }

    nonisolated private static func appendToFile(_ level: String, _ category: String, _ message: String) {
        guard let fileURL else { return }
        lock.lock(); defer { lock.unlock() }
        let line = "\(formatter.string(from: Date())) [\(level)] [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        rotateIfNeeded(at: fileURL)
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    nonisolated static func debug(_ message: String, category: String = "App") {
        logger(category).debug("\(message, privacy: .public)")
        appendToFile("DEBUG", category, message)
    }

    nonisolated static func info(_ message: String, category: String = "App") {
        logger(category).info("\(message, privacy: .public)")
        appendToFile("INFO", category, message)
    }

    nonisolated static func warn(_ message: String, category: String = "App") {
        logger(category).notice("\(message, privacy: .public)")
        appendToFile("WARN", category, message)
    }

    nonisolated static func error(_ message: String, category: String = "App") {
        logger(category).error("\(message, privacy: .public)")
        appendToFile("ERROR", category, message)
    }
}
