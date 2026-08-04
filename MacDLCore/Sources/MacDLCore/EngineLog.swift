import Foundation
import os

/// Best-effort appender that mirrors log lines to a file alongside the unified
/// log, so a bug can be reproduced and the file inspected directly. Never
/// crashes the app on failure.
public enum FileLogWriter {
    /// Where log lines are appended. Set once at launch.
    public nonisolated(unsafe) static var logFileURL: URL?

    private static let lock = NSLock()
    private nonisolated(unsafe) static var handle: FileHandle?

    /// Switches the log destination and truncates the file for a fresh run.
    public static func setLogFile(_ url: URL?) {
        lock.lock()
        if let url {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: url)
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        logFileURL = url
        handle = nil
        lock.unlock()
    }

    static func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        guard let url = logFileURL else { return }
        do {
            if handle == nil {
                guard let fh = try? FileHandle(forWritingTo: url) else { return }
                fh.seekToEndOfFile()
                handle = fh
            }
            try handle?.write(contentsOf: (line + "\n").data(using: .utf8) ?? Data())
        } catch {
            // best-effort logging only
        }
    }
}

// Logging category that mirrors to both the unified log and the log file.
/// Log helper mirroring every line to the unified log and the log file.
public final class LogCategory: @unchecked Sendable {
    private let osLogger: Logger
    private let category: String

    init(category: String) {
        self.category = category
        self.osLogger = Logger(subsystem: "com.xiaowu.MacDL", category: category)
    }

    /// Writes a debug-level line to both the file and the unified log.
    public func debug(_ message: String) { write("DEBUG", message); osLogger.debug("\(message, privacy: .public)") }
    /// Writes an info-level line to both the file and the unified log.
    public func notice(_ message: String) { write("INFO", message); osLogger.notice("\(message, privacy: .public)") }
    /// Writes a warn-level line to both the file and the unified log.
    public func warning(_ message: String) { write("WARN", message); osLogger.warning("\(message, privacy: .public)") }
    /// Writes an error-level line to both the file and the unified log.
    public func error(_ message: String) { write("ERROR", message); osLogger.error("\(message, privacy: .public)") }

    private func write(_ level: String, _ message: String) {
        FileLogWriter.append("\(Self.timestamp) [\(category)] \(level) \(message)")
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static var timestamp: String {
        timestampFormatter.string(from: Date())
    }
}

// Unified logging. One subsystem (the app's bundle id) with per-area categories,
// so Console.app can filter to MacDL and hide the noisy Network.framework lines.
/// Logging entry points, one per engine area, sharing the app's bundle subsystem.
public enum EngineLog {
    /// Chunk scheduling / lifecycle events.
    public nonisolated(unsafe) static let manager = LogCategory(category: "engine.manager")
    /// Per-chunk request and write events.
    public nonisolated(unsafe) static let chunk = LogCategory(category: "engine.chunk")
    /// App-level lifecycle events.
    public nonisolated(unsafe) static let app = LogCategory(category: "app")
}
