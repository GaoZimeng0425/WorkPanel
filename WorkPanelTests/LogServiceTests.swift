import Testing
import Foundation
@testable import WorkPanel

/// 轮转决策是纯函数(URL 可注入);写入路径本身不测(AppKit 常驻文件,别碰真机日志)。
struct LogServiceTests {
    private func makeTempLog(bytes: Int) throws -> (dir: URL, file: URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("workpanel.log")
        try Data(count: bytes).write(to: file)
        return (dir, file)
    }

    @Test func rotatesWhenOverLimit() throws {
        let (dir, file) = try makeTempLog(bytes: 100)
        defer { try? FileManager.default.removeItem(at: dir) }
        LogService.rotateIfNeeded(at: file, maxBytes: 50)
        #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("old").path))
        #expect(!FileManager.default.fileExists(atPath: file.path))   // 原文件已被移走
    }

    @Test func keepsFileUnderLimit() throws {
        let (dir, file) = try makeTempLog(bytes: 40)
        defer { try? FileManager.default.removeItem(at: dir) }
        LogService.rotateIfNeeded(at: file, maxBytes: 50)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: file.appendingPathExtension("old").path))
    }

    @Test func missingFileIsNoOp() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LogServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let ghost = dir.appendingPathComponent("ghost.log")
        LogService.rotateIfNeeded(at: ghost, maxBytes: 1)   // 不得抛错
        #expect(!FileManager.default.fileExists(atPath: ghost.path))
    }

    @Test func rotationOverwritesPreviousOld() throws {
        let (dir, file) = try makeTempLog(bytes: 100)
        defer { try? FileManager.default.removeItem(at: dir) }
        let old = file.appendingPathExtension("old")
        try Data(count: 1).write(to: old)
        LogService.rotateIfNeeded(at: file, maxBytes: 50)
        let size = (try FileManager.default.attributesOfItem(atPath: old.path)[.size] as? NSNumber)?.intValue
        #expect(size == 100)   // 旧 .old 被覆盖,不是追加
    }
}
