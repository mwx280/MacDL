import Foundation

/// Top-level facade of the chunked download engine. Keeps one ``ChunkManager``
/// per download id and forwards every control call through a serial queue, so
/// the app never races the engine's internal state.
public final class DownloadEngine: @unchecked Sendable, DownloadEngineProtocol {

    /// App-wide default engine instance.
    public static let shared = DownloadEngine()

    private var managers: [UUID: ChunkManager] = [:]
    private let syncQueue = DispatchQueue(label: "com.xiaowu.downloadengine.sync")

    /// Creates an empty engine with no tracked downloads.
    public init() {}

    /// Starts a download, or restarts it with fresh state.
    /// - Parameters:
    ///   - mirrors: Additional source URLs the download fails over to when the
    ///     primary source is cooling down.
    ///   - chunks: Persisted chunks to resume from. Empty starts a Range probe
    ///     and builds the chunk list from the server's reported size.
    public func start(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, chunkSize: Int64 = 262144, maxConcurrent: Int = 4, chunks: [Chunk] = [], mirrors: [URL] = []) {
        let manager = ChunkManager(id: id, url: url, destinationURL: destinationURL, chunkSize: chunkSize, maxConcurrent: maxConcurrent, mirrors: mirrors)
        manager.setSpeedLimit(speedLimit)
        syncQueue.sync {
            managers[id]?.cancel()
            managers[id] = manager
        }
        if chunks.isEmpty {
            manager.start()
        } else {
            let totalSize = chunks.last?.endOffset ?? 0
            manager.start(withChunks: chunks, totalSize: totalSize)
        }
    }

    /// Resumes a paused download. Returns false when no task is tracked for the id.
    public func resume(id: UUID) -> Bool {
        syncQueue.sync {
            guard let manager = managers[id] else { return false }
            manager.resume()
            return true
        }
    }

    /// Pauses the download: freezes scheduling, cancels in-flight tasks and
    /// clears the pending queue so nothing restarts while paused.
    public func pause(id: UUID) {
        syncQueue.sync { _ = managers[id]?.pause() }
    }

    /// Cancels the download and drops its in-memory state.
    public func cancel(id: UUID) {
        syncQueue.sync {
            _ = managers[id]?.cancel()
            _ = managers.removeValue(forKey: id)
        }
    }

    /// Removes the manager without signalling it; used after a download finished.
    public func cleanup(id: UUID) {
        syncQueue.sync {
            _ = managers.removeValue(forKey: id)
        }
    }

    /// Updates the per-download byte/second throttle.
    public func setSpeedLimit(id: UUID, limit: Int64) {
        syncQueue.sync { _ = managers[id]?.setSpeedLimit(limit) }
    }

    /// Updates the per-download parallel-connection cap.
    public func setMaxConcurrent(id: UUID, max: Int) {
        syncQueue.sync { _ = managers[id]?.setMaxConcurrent(max) }
    }

    /// True while any tracked download is actively transferring bytes.
    public var hasActiveTasks: Bool {
        syncQueue.sync { managers.values.contains { $0.hasActiveTasks } }
    }

    /// Registers the progress callback: `(writtenBytes, totalBytes, bytesPerSecond)`.
    public func setProgressHandler(for id: UUID, handler: @escaping (Int64, Int64, Int64) -> Void) {
        syncQueue.sync { managers[id]?.onProgress = handler }
    }

    /// Registers the completion callback with the overall `Result<Void, Error>`.
    public func setCompletionHandler(for id: UUID, handler: @escaping (Result<Void, Error>) -> Void) {
        syncQueue.sync { managers[id]?.onCompletion = handler }
    }

    /// Registers the chunk-array callback (delivered at most every
    /// `chunksChangedInterval` seconds; structural changes force an immediate copy).
    public func setChunksChangeHandler(for id: UUID, handler: @escaping ([Chunk]) -> Void) {
        syncQueue.sync { managers[id]?.onChunksChanged = handler }
    }

    /// Registers the incremental chunk callback (only chunks that changed since
    /// the last delivery, avoiding a full-array copy on every progress tick).
    public func setChunksUpdateHandler(for id: UUID, handler: @escaping ([Chunk]) -> Void) {
        syncQueue.sync { managers[id]?.onChunksUpdated = handler }
    }

    /// Registers the resume-support callback; `false` means the server ignores
    /// Range requests and the download falls back to a single stream.
    public func setResumeSupportHandler(for id: UUID, handler: @escaping (Bool) -> Void) {
        syncQueue.sync { managers[id]?.onResumeSupport = handler }
    }

    /// Registers the phase callback: `true` while the Range probe runs (no
    /// chunks scheduled yet), `false` once chunks or a single stream start.
    public func setPhaseHandler(for id: UUID, handler: @escaping (Bool) -> Void) {
        syncQueue.sync { managers[id]?.onPhaseChanged = handler }
    }

    /// Registers the chunk-size callback, fired once the probe picks a dynamic
    /// chunk size for the file.
    public func setChunkSizeHandler(for id: UUID, handler: @escaping (Int64) -> Void) {
        syncQueue.sync { managers[id]?.onChunkSizeChanged = handler }
    }
}
