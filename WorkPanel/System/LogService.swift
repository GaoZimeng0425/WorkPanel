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

    nonisolated private static func appendToFile(_ level: String, _ category: String, _ message: String) {
        guard let fileURL else { return }
        let line = "\(Self.timestamp()) [\(level)] [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        lock.lock(); defer { lock.unlock() }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: fileURL)
        }
    }

    nonisolated private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
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
