import Foundation

/// Engine boundary so the app drives downloads (or a test double) without
/// depending on the concrete ``DownloadEngine`` implementation.
public protocol DownloadEngineProtocol {
    /// Starts a download, resuming persisted chunks when provided. Bypasses the
    /// global concurrency cap (resume/retry semantics).
    func start(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk], mirrors: [URL])
    /// Schedules a download against the global concurrency cap; returns true
    /// when it started now (false = queued).
    func schedule(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk], mirrors: [URL]) -> Bool
    /// Registers a download into the waiting queue without starting it.
    func enqueue(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk], mirrors: [URL])
    /// Sets the global cap on simultaneously running downloads.
    func setMaxConcurrentDownloads(_ limit: Int)
    /// Registers the callback fired when a queued download is promoted to running.
    func setPromotionHandler(_ handler: @escaping (UUID) -> Void)
    /// Registers the callback fired when the engine pauses a download for a
    /// priority download.
    func setPriorityPausedHandler(_ handler: @escaping (UUID) -> Void)
    /// Registers the callback fired when a priority-paused download is restored.
    func setPriorityResumedHandler(_ handler: @escaping (UUID) -> Void)
    /// Marks a download as priority: pauses other running downloads and starts
    /// the priority one if needed.
    func setPriorityDownload(_ id: UUID)
    /// Ends priority mode, signalling every priority-paused download to resume.
    func endPriority(excluding skip: UUID?)
    /// Re-registers the priority-paused set after a restart.
    func registerPriorityPaused(_ ids: Set<UUID>)
    /// Starts monitoring the system link; downloads hold chunks while it is down
    /// and resume when it returns.
    func startMonitoringNetwork()
    /// Registers the callback fired when the system link state changes
    /// (`true` = network available).
    func setNetworkChangeHandler(_ handler: @escaping (Bool) -> Void)
    /// Resumes a paused download; false when nothing is tracked for the id.
    func resume(id: UUID) -> Bool
    /// Pauses the download.
    func pause(id: UUID)
    /// Cancels the download and drops its state (running or queued).
    func cancel(id: UUID)
    /// Removes the manager without signalling it.
    func cleanup(id: UUID)
    /// Updates the per-download byte/second throttle.
    func setSpeedLimit(id: UUID, limit: Int64)
    /// Updates the per-download parallel-connection cap.
    func setMaxConcurrent(id: UUID, max: Int)
    /// True while any tracked download is actively transferring.
    var hasActiveTasks: Bool { get }
    /// Registers the `(written, total, speed)` progress callback.
    func setProgressHandler(for id: UUID, handler: @escaping (Int64, Int64, Int64) -> Void)
    /// Registers the completion callback.
    func setCompletionHandler(for id: UUID, handler: @escaping (Result<Void, Error>) -> Void)
    /// Registers the chunk-array callback (full array, structural changes).
    func setChunksChangeHandler(for id: UUID, handler: @escaping ([Chunk]) -> Void)
    /// Registers the incremental chunk callback (only chunks that changed).
    func setChunksUpdateHandler(for id: UUID, handler: @escaping ([Chunk]) -> Void)
    /// Registers the server-resume-support callback.
    func setResumeSupportHandler(for id: UUID, handler: @escaping (Bool) -> Void)
    /// Registers the probe-phase callback (`true` while probing).
    func setPhaseHandler(for id: UUID, handler: @escaping (Bool) -> Void)
    /// Registers the chunk-size callback, fired when the probe picks a dynamic
    /// chunk size.
    func setChunkSizeHandler(for id: UUID, handler: @escaping (Int64) -> Void)
    /// Registers the retrying callback: `true` while a stalled transfer is being
    /// re-established, `false` once bytes flow again or the download ends.
    func setRetryingHandler(for id: UUID, handler: @escaping (Bool) -> Void)
}
