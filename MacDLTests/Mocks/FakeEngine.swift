import Foundation
import MacDLCore

// A fake engine that records calls and can fire callbacks, used for ContentViewModel action unit tests.
final class FakeEngine: DownloadEngineProtocol {
    var started: [UUID] = []
    var scheduled: [UUID] = []
    var queued: [UUID] = []
    var resumed: [UUID] = []
    var paused: [UUID] = []
    var cancelled: [UUID] = []
    var cleaned: [UUID] = []
    var speedLimits: [UUID: Int64] = [:]
    var maxConcurrents: [UUID: Int] = [:]
    var maxConcurrentDownloads = 5
    var resumeResult = false
    var hasActiveTasks = false
    var scheduleResult: [UUID: Bool] = [:]

    private var progressHandlers: [UUID: (Int64, Int64, Int64) -> Void] = [:]
    private var completionHandlers: [UUID: (Result<Void, Error>) -> Void] = [:]
    private var chunksChangeHandlers: [UUID: ([Chunk]) -> Void] = [:]
    private var chunksUpdateHandlers: [UUID: ([Chunk]) -> Void] = [:]
    private var resumeSupportHandlers: [UUID: (Bool) -> Void] = [:]
    private var phaseHandlers: [UUID: (Bool) -> Void] = [:]
    private var chunkSizeHandlers: [UUID: (Int64) -> Void] = [:]
    private var retryingHandlers: [UUID: (Bool) -> Void] = [:]
    private var promotionHandlers: [(UUID) -> Void] = []
    private var running = Set<UUID>()

    func start(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk], mirrors: [URL]) {
        started.append(id)
        running.insert(id)
    }

    func schedule(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk], mirrors: [URL]) -> Bool {
        scheduled.append(id)
        let result = scheduleResult[id] ?? (running.count < maxConcurrentDownloads)
        if result {
            started.append(id)
            running.insert(id)
        } else {
            queued.append(id)
        }
        return result
    }

    func enqueue(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk], mirrors: [URL]) {
        queued.append(id)
    }

    func setMaxConcurrentDownloads(_ limit: Int) {
        maxConcurrentDownloads = limit
        // Simulate the engine's scheduler promoting queued downloads when a slot
        // frees (fires the promotion handler).
        while running.count < maxConcurrentDownloads, !queued.isEmpty {
            firePromotion(id: queued.removeFirst())
        }
    }

    func setPromotionHandler(_ handler: @escaping (UUID) -> Void) {
        promotionHandlers.append(handler)
    }

    func resume(id: UUID) -> Bool {
        resumed.append(id)
        if resumeResult { running.insert(id) }
        return resumeResult
    }

    func pause(id: UUID) {
        paused.append(id)
        running.remove(id)
    }

    func cancel(id: UUID) {
        cancelled.append(id)
        running.remove(id)
        queued.removeAll { $0 == id }
    }

    func cleanup(id: UUID) { cleaned.append(id) }

    func setSpeedLimit(id: UUID, limit: Int64) { speedLimits[id] = limit }
    func setMaxConcurrent(id: UUID, max: Int) { maxConcurrents[id] = max }

    func setProgressHandler(for id: UUID, handler: @escaping (Int64, Int64, Int64) -> Void) {
        progressHandlers[id] = handler
    }

    func setCompletionHandler(for id: UUID, handler: @escaping (Result<Void, Error>) -> Void) {
        completionHandlers[id] = handler
    }

    func setChunksChangeHandler(for id: UUID, handler: @escaping ([Chunk]) -> Void) {
        chunksChangeHandlers[id] = handler
    }

    func setChunksUpdateHandler(for id: UUID, handler: @escaping ([Chunk]) -> Void) {
        chunksUpdateHandlers[id] = handler
    }

    func setResumeSupportHandler(for id: UUID, handler: @escaping (Bool) -> Void) {
        resumeSupportHandlers[id] = handler
    }

    func setPhaseHandler(for id: UUID, handler: @escaping (Bool) -> Void) {
        phaseHandlers[id] = handler
    }

    func setChunkSizeHandler(for id: UUID, handler: @escaping (Int64) -> Void) {
        chunkSizeHandlers[id] = handler
    }

    func setRetryingHandler(for id: UUID, handler: @escaping (Bool) -> Void) {
        retryingHandlers[id] = handler
    }

    func fireProgress(id: UUID, downloaded: Int64, total: Int64, speed: Int64 = 0) {
        progressHandlers[id]?(downloaded, total, speed)
    }

    func fireCompletion(id: UUID, result: Result<Void, Error>) {
        completionHandlers[id]?(result)
    }

    func fireResumeSupport(id: UUID, supported: Bool) {
        resumeSupportHandlers[id]?(supported)
    }

    func firePhase(id: UUID, isProbing: Bool) {
        phaseHandlers[id]?(isProbing)
    }

    func fireRetrying(id: UUID, retrying: Bool) {
        retryingHandlers[id]?(retrying)
    }

    func firePromotion(id: UUID) {
        running.insert(id)
        queued.removeAll { $0 == id }
        started.append(id)
        for handler in promotionHandlers { handler(id) }
    }
}
