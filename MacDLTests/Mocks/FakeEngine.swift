import Foundation
import MacDLCore

// A fake engine that records calls and can fire callbacks, used for ContentViewModel action unit tests.
final class FakeEngine: DownloadEngineProtocol {
    var started: [UUID] = []
    var resumed: [UUID] = []
    var paused: [UUID] = []
    var cancelled: [UUID] = []
    var cleaned: [UUID] = []
    var speedLimits: [UUID: Int64] = [:]
    var maxConcurrents: [UUID: Int] = [:]
    var resumeResult = false
    var hasActiveTasks = false

    private var progressHandlers: [UUID: (Int64, Int64, Int64) -> Void] = [:]
    private var completionHandlers: [UUID: (Result<Void, Error>) -> Void] = [:]
    private var chunksChangeHandlers: [UUID: ([Chunk]) -> Void] = [:]
    private var resumeSupportHandlers: [UUID: (Bool) -> Void] = [:]

    func start(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, chunkSize: Int64, maxConcurrent: Int, chunks: [Chunk]) {
        started.append(id)
    }

    func resume(id: UUID) -> Bool {
        resumed.append(id)
        return resumeResult
    }

    func pause(id: UUID) { paused.append(id) }
    func cancel(id: UUID) { cancelled.append(id) }
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

    func setResumeSupportHandler(for id: UUID, handler: @escaping (Bool) -> Void) {
        resumeSupportHandlers[id] = handler
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
}
