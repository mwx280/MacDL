import Foundation

/// Top-level facade of the chunked download engine. Keeps one ``ChunkManager``
/// per download id, schedules downloads against a global concurrency cap via a
/// ``DownloadScheduler``, and forwards every control call through a serial
/// queue, so the app never races the engine's internal state.
public final class DownloadEngine: @unchecked Sendable, DownloadEngineProtocol {

    /// App-wide default engine instance.
    public static let shared = DownloadEngine()

    private var managers: [UUID: ChunkManager] = [:]
    private var pendingStarts: [UUID: PendingStart] = [:]
    private var handlers: [UUID: HandlerBundle] = [:]
    // Downloads cancelled by the app (delete / cancel). Their managers' late
    // completion callbacks must not forward to the app or promote a queued
    // download — the app already handled the removal itself.
    private var discarded: Set<UUID> = []
    private let scheduler = DownloadScheduler(capacity: 1)
    private var onPromoted: ((UUID) -> Void)?
    private let syncQueue = DispatchQueue(label: "com.xiaowu.downloadengine.sync")

    /// Start parameters retained for a queued download until it is promoted.
    private struct PendingStart {
        let url: URL
        let destinationURL: URL
        let speedLimit: Int64
        let chunkSize: Int64
        let maxConcurrent: Int
        let chunks: [Chunk]
        let mirrors: [URL]
    }

    /// Handlers registered per download. Buffered for queued downloads and
    /// applied when their manager is created; for running downloads the
    /// non-completion handlers are also applied live.
    private struct HandlerBundle {
        var onProgress: ((Int64, Int64, Int64) -> Void)?
        var onChunksChanged: (([Chunk]) -> Void)?
        var onChunksUpdated: (([Chunk]) -> Void)?
        var onResumeSupport: ((Bool) -> Void)?
        var onPhaseChanged: ((Bool) -> Void)?
        var onChunkSizeChanged: ((Int64) -> Void)?
        var onRetrying: ((Bool) -> Void)?
        var onCompletion: ((Result<Void, Error>) -> Void)?
    }

    /// Creates an empty engine with no tracked downloads.
    public init() {}

    // MARK: - Scheduling

    /// Sets the global cap on simultaneously running downloads. A grown cap
    /// promotes queued downloads immediately.
    public func setMaxConcurrentDownloads(_ limit: Int) {
        syncQueue.sync {
            for promoted in scheduler.setCapacity(limit) {
                startNow(promoted)
                onPromoted?(promoted)
            }
        }
    }

    /// Registers the callback fired when a queued download is promoted to
    /// running (so the app can flip its status to active).
    public func setPromotionHandler(_ handler: @escaping (UUID) -> Void) {
        syncQueue.sync { onPromoted = handler }
    }

    /// Schedules a download against the concurrency cap: starts it immediately
    /// when a slot is free, otherwise queues it FIFO. Returns `true` when it
    /// started now.
    public func schedule(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, chunkSize: Int64 = 262144, maxConcurrent: Int = 4, chunks: [Chunk] = [], mirrors: [URL] = []) -> Bool {
        syncQueue.sync {
            discarded.remove(id)
            pendingStarts[id] = PendingStart(url: url, destinationURL: destinationURL, speedLimit: speedLimit, chunkSize: chunkSize, maxConcurrent: maxConcurrent, chunks: chunks, mirrors: mirrors)
            let shouldStart = scheduler.schedule(id)
            if shouldStart { startNow(id) }
            return shouldStart
        }
    }

    /// Registers a download into the waiting queue without starting it (used to
    /// restore persisted waiting downloads on launch).
    public func enqueue(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, chunkSize: Int64 = 262144, maxConcurrent: Int = 4, chunks: [Chunk] = [], mirrors: [URL] = []) {
        syncQueue.sync {
            discarded.remove(id)
            pendingStarts[id] = PendingStart(url: url, destinationURL: destinationURL, speedLimit: speedLimit, chunkSize: chunkSize, maxConcurrent: maxConcurrent, chunks: chunks, mirrors: mirrors)
            scheduler.enqueue(id)
        }
    }

    /// Starts a download immediately, bypassing the concurrency cap. Used by
    /// resume/retry, which the app treats as urgent.
    public func start(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, chunkSize: Int64 = 262144, maxConcurrent: Int = 4, chunks: [Chunk] = [], mirrors: [URL] = []) {
        syncQueue.sync {
            discarded.remove(id)
            pendingStarts[id] = PendingStart(url: url, destinationURL: destinationURL, speedLimit: speedLimit, chunkSize: chunkSize, maxConcurrent: maxConcurrent, chunks: chunks, mirrors: mirrors)
            scheduler.forceRun(id)
            startNow(id)
        }
    }

    /// Creates the manager for `id` from its stored start parameters, attaches
    /// its buffered handlers and begins the transfer. Call on syncQueue.
    private func startNow(_ id: UUID) {
        guard let start = pendingStarts[id] else { return }
        let manager = ChunkManager(id: id, url: start.url, destinationURL: start.destinationURL, chunkSize: start.chunkSize, maxConcurrent: start.maxConcurrent, mirrors: start.mirrors)
        manager.setSpeedLimit(start.speedLimit)
        applyHandlers(to: manager, id: id)
        managers[id]?.cancel()
        managers[id] = manager
        if start.chunks.isEmpty {
            manager.start()
        } else {
            let totalSize = start.chunks.last?.endOffset ?? 0
            manager.start(withChunks: start.chunks, totalSize: totalSize)
        }
    }

    /// Installs the buffered non-completion handlers plus the completion
    /// wrapper (which forwards completion and promotes the next queued
    /// download). Call on syncQueue.
    private func applyHandlers(to manager: ChunkManager, id: UUID) {
        if let h = handlers[id] {
            manager.onProgress = h.onProgress
            manager.onChunksChanged = h.onChunksChanged
            manager.onChunksUpdated = h.onChunksUpdated
            manager.onResumeSupport = h.onResumeSupport
            manager.onPhaseChanged = h.onPhaseChanged
            manager.onChunkSizeChanged = h.onChunkSizeChanged
            manager.onRetrying = h.onRetrying
        }
        manager.onCompletion = { [weak self] result in
            guard let self else { return }
            self.syncQueue.sync {
                // A cancelled/deleted download's late completion must neither
                // forward to the app nor promote a queued download, and must not
                // drop a replacement manager that reused the same id.
                let wasDiscarded = self.discarded.remove(id) != nil
                let userCompletion = self.handlers[id]?.onCompletion
                if self.managers[id] === manager {
                    self.managers.removeValue(forKey: id)
                    self.handlers[id] = nil
                }
                guard !wasDiscarded else { return }
                userCompletion?(result)
                for promoted in self.scheduler.finished(id) {
                    self.startNow(promoted)
                    self.onPromoted?(promoted)
                }
            }
        }
    }

    // MARK: - Control

    /// Resumes a paused download. Returns false when no task is tracked for the id.
    public func resume(id: UUID) -> Bool {
        syncQueue.sync {
            guard let manager = managers[id] else { return false }
            scheduler.forceRun(id)
            manager.resume()
            return true
        }
    }

    /// Pauses the download: freezes scheduling, cancels in-flight tasks and
    /// clears the pending queue so nothing restarts while paused. Releases the
    /// download's scheduling slot without starting a queued replacement.
    public func pause(id: UUID) {
        syncQueue.sync {
            _ = managers[id]?.pause()
            scheduler.discard(id)
        }
    }

    /// Cancels the download and drops its in-memory state (running or queued).
    /// The app handles the aftermath (deletion, error marking) itself, so the
    /// manager's late completion callback is suppressed.
    public func cancel(id: UUID) {
        syncQueue.sync {
            _ = managers[id]?.cancel()
            _ = managers.removeValue(forKey: id)
            pendingStarts.removeValue(forKey: id)
            handlers.removeValue(forKey: id)
            scheduler.discard(id)
            discarded.insert(id)
        }
    }

    /// Removes the manager without signalling it; used after a download finished.
    public func cleanup(id: UUID) {
        syncQueue.sync {
            _ = managers.removeValue(forKey: id)
            pendingStarts.removeValue(forKey: id)
            handlers.removeValue(forKey: id)
            discarded.remove(id)
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

    // MARK: - Handlers

    /// Registers the progress callback: `(writtenBytes, totalBytes, bytesPerSecond)`.
    public func setProgressHandler(for id: UUID, handler: @escaping (Int64, Int64, Int64) -> Void) {
        syncQueue.sync {
            if handlers[id] == nil { handlers[id] = HandlerBundle() }
            handlers[id]?.onProgress = handler
            managers[id]?.onProgress = handler
        }
    }

    /// Registers the completion callback with the overall `Result<Void, Error>`.
    public func setCompletionHandler(for id: UUID, handler: @escaping (Result<Void, Error>) -> Void) {
        syncQueue.sync {
            if handlers[id] == nil { handlers[id] = HandlerBundle() }
            handlers[id]?.onCompletion = handler
        }
    }

    /// Registers the chunk-array callback (delivered at most every
    /// `chunksChangedInterval` seconds; structural changes force an immediate copy).
    public func setChunksChangeHandler(for id: UUID, handler: @escaping ([Chunk]) -> Void) {
        syncQueue.sync {
            if handlers[id] == nil { handlers[id] = HandlerBundle() }
            handlers[id]?.onChunksChanged = handler
            managers[id]?.onChunksChanged = handler
        }
    }

    /// Registers the incremental chunk callback (only chunks that changed since
    /// the last delivery, avoiding a full-array copy on every progress tick).
    public func setChunksUpdateHandler(for id: UUID, handler: @escaping ([Chunk]) -> Void) {
        syncQueue.sync {
            if handlers[id] == nil { handlers[id] = HandlerBundle() }
            handlers[id]?.onChunksUpdated = handler
            managers[id]?.onChunksUpdated = handler
        }
    }

    /// Registers the resume-support callback; `false` means the server ignores
    /// Range requests and the download falls back to a single stream.
    public func setResumeSupportHandler(for id: UUID, handler: @escaping (Bool) -> Void) {
        syncQueue.sync {
            if handlers[id] == nil { handlers[id] = HandlerBundle() }
            handlers[id]?.onResumeSupport = handler
            managers[id]?.onResumeSupport = handler
        }
    }

    /// Registers the phase callback: `true` while the Range probe runs (no
    /// chunks scheduled yet), `false` once chunks or a single stream start.
    public func setPhaseHandler(for id: UUID, handler: @escaping (Bool) -> Void) {
        syncQueue.sync {
            if handlers[id] == nil { handlers[id] = HandlerBundle() }
            handlers[id]?.onPhaseChanged = handler
            managers[id]?.onPhaseChanged = handler
        }
    }

    /// Registers the chunk-size callback, fired once the probe picks a dynamic
    /// chunk size for the file.
    public func setChunkSizeHandler(for id: UUID, handler: @escaping (Int64) -> Void) {
        syncQueue.sync {
            if handlers[id] == nil { handlers[id] = HandlerBundle() }
            handlers[id]?.onChunkSizeChanged = handler
            managers[id]?.onChunkSizeChanged = handler
        }
    }

    /// Registers the retrying callback: `true` while a stalled transfer is being
    /// re-established, `false` once bytes flow again or the download ends.
    public func setRetryingHandler(for id: UUID, handler: @escaping (Bool) -> Void) {
        syncQueue.sync {
            if handlers[id] == nil { handlers[id] = HandlerBundle() }
            handlers[id]?.onRetrying = handler
            managers[id]?.onRetrying = handler
        }
    }
}
