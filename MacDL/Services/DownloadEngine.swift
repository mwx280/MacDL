import Foundation

final class DownloadEngine {

    static let shared = DownloadEngine()

    private var managers: [UUID: ChunkManager] = [:]
    private let syncQueue = DispatchQueue(label: "com.xiaowu.downloadengine.sync")

    private init() {}

    func start(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, resumeFrom: Int64 = 0, chunkSize: Int64 = 262144, maxConcurrent: Int = 4, chunks: [Chunk] = []) {
        let manager = ChunkManager(id: id, url: url, destinationURL: destinationURL, chunkSize: chunkSize, maxConcurrent: maxConcurrent)
        manager.setSpeedLimit(speedLimit)
        syncQueue.sync { managers[id] = manager }
        if chunks.isEmpty {
            manager.start()
        } else {
            let totalSize = chunks.last?.endOffset ?? resumeFrom
            manager.start(withChunks: chunks, totalSize: totalSize)
        }
    }

    func resume(id: UUID) -> Bool {
        syncQueue.sync {
            guard let manager = managers[id] else { return false }
            manager.resume()
            return true
        }
    }

    func pause(id: UUID) {
        syncQueue.sync { _ = managers[id]?.pause() }
    }

    func cancel(id: UUID) {
        syncQueue.sync {
            _ = managers[id]?.cancel()
            _ = managers.removeValue(forKey: id)
        }
    }

    func cleanup(id: UUID) {
        syncQueue.sync {
            _ = managers.removeValue(forKey: id)
        }
    }

    func setSpeedLimit(id: UUID, limit: Int64) {
        syncQueue.sync { _ = managers[id]?.setSpeedLimit(limit) }
    }

    func setMaxConcurrent(id: UUID, max: Int) {
        syncQueue.sync { _ = managers[id]?.setMaxConcurrent(max) }
    }

    var hasActiveTasks: Bool {
        syncQueue.sync { managers.values.contains { $0.hasActiveTasks } }
    }

    func setProgressHandler(for id: UUID, handler: @escaping (Int64, Int64, Int64) -> Void) {
        syncQueue.sync { managers[id]?.onProgress = handler }
    }

    func setCompletionHandler(for id: UUID, handler: @escaping (Result<Void, Error>) -> Void) {
        syncQueue.sync { managers[id]?.onCompletion = handler }
    }

    func setChunksChangeHandler(for id: UUID, handler: @escaping ([Chunk]) -> Void) {
        syncQueue.sync { managers[id]?.onChunksChanged = handler }
    }

    func setResumeSupportHandler(for id: UUID, handler: @escaping (Bool) -> Void) {
        syncQueue.sync { managers[id]?.onResumeSupport = handler }
    }
}
