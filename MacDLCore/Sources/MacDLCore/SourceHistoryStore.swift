import Foundation

/// Per-host download statistics persisted across sessions, so a source that is
/// downloaded repeatedly starts at its previously-learned optimal connection
/// count and chunk size instead of re-probing from scratch every time.
///
/// Uses plain EWMA statistics (bandwidth / RTT) plus success counts — no machine
/// learning, no external dependencies. Stored locally; the app injects the
/// on-disk location via ``setFileURL(_:)``.
public struct SourceHistory: Codable, Equatable, Sendable {
    public let host: String
    /// EWMA of observed aggregate throughput, bytes/second.
    public var avgBandwidth: Int64
    /// EWMA of the probe RTT, seconds.
    public var avgRTT: TimeInterval
    public var successCount: Int
    public var failureCount: Int
    /// Last known server Range (resume) support.
    public var supportsRange: Bool?
    public var sampleCount: Int
    public var lastSeen: Date

    public var successRate: Double {
        let total = successCount + failureCount
        return total > 0 ? Double(successCount) / Double(total) : 1
    }

    public init(host: String, avgBandwidth: Int64, avgRTT: TimeInterval,
                successCount: Int = 0, failureCount: Int = 0,
                supportsRange: Bool? = nil, sampleCount: Int = 0,
                lastSeen: Date = Date()) {
        self.host = host
        self.avgBandwidth = avgBandwidth
        self.avgRTT = avgRTT
        self.successCount = successCount
        self.failureCount = failureCount
        self.supportsRange = supportsRange
        self.sampleCount = sampleCount
        self.lastSeen = lastSeen
    }
}

/// Thread-safe store of ``SourceHistory`` entries keyed by host, persisted as
/// JSON. Reads and writes are guarded by a lock; persistence runs on a private
/// background queue so it never blocks the engine's serial queue.
public final class SourceHistoryStore: @unchecked Sendable {
    public static let shared = SourceHistoryStore()

    /// How much weight a new sample carries in the EWMA (0..1).
    private static let ewmaWeight = 0.2

    private var history: [String: SourceHistory] = [:]
    private let lock = NSLock()
    private let ioQueue = DispatchQueue(label: "com.xiaowu.sourcehistory.io", qos: .utility)
    private var fileURL: URL?

    private init() {}

    /// Sets the on-disk location and loads any existing history. Pass `nil` to
    /// keep the store in-memory only (tests).
    public func setFileURL(_ url: URL?) {
        lock.lock()
        fileURL = url
        lock.unlock()
        if url != nil { load() }
    }

    /// Returns the history for a host, or `nil` when unknown.
    public func history(for host: String) -> SourceHistory? {
        lock.lock()
        defer { lock.unlock() }
        return history[host]
    }

    /// Clears all in-memory history (used by tests).
    public func removeAll() {
        lock.lock()
        history.removeAll()
        lock.unlock()
    }

    /// Blocks until any pending persistence is written (used by tests and on
    /// shutdown so no history is lost).
    public func flush() {
        ioQueue.sync {}
    }

    /// Records one completed (or failed) download against a host and merges it
    /// into the EWMA statistics.
    public func record(host: String, bandwidth: Int64, rtt: TimeInterval,
                       success: Bool, supportsRange: Bool?) {
        lock.lock()
        var entry = history[host] ?? SourceHistory(host: host, avgBandwidth: bandwidth,
                                                   avgRTT: rtt, supportsRange: supportsRange)
        if entry.sampleCount == 0 {
            entry.avgBandwidth = bandwidth
            entry.avgRTT = rtt
        } else {
            let w = Self.ewmaWeight
            entry.avgBandwidth = Int64((Double(entry.avgBandwidth) * (1 - w)) + (Double(bandwidth) * w))
            entry.avgRTT = (entry.avgRTT * (1 - w)) + (rtt * w)
        }
        entry.sampleCount += 1
        if success { entry.successCount += 1 } else { entry.failureCount += 1 }
        if let supportsRange { entry.supportsRange = supportsRange }
        entry.lastSeen = Date()
        history[host] = entry
        let snapshot = history
        lock.unlock()
        persist(snapshot)
    }

    // MARK: - Persistence

    private func load() {
        lock.lock()
        let url = fileURL
        lock.unlock()
        guard let url,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: SourceHistory].self, from: data)
        else { return }
        lock.lock()
        history = decoded
        lock.unlock()
    }

    private func persist(_ snapshot: [String: SourceHistory]) {
        lock.lock()
        let url = fileURL
        lock.unlock()
        guard let url else { return }
        ioQueue.async {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                     withIntermediateDirectories: true)
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
