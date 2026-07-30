import Foundation

final class DownloadEngine {

    static let shared = DownloadEngine()

    private var managers: [UUID: ChunkManager] = [:]
    private let syncQueue = DispatchQueue(label: "com.xiaowu.downloadengine.sync")

    private init() {}

    func start(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, resumeFrom: Int64 = 0, chunkSize: Int64 = 262144, maxConcurrent: Int = 4) {
        let manager = ChunkManager(id: id, url: url, destinationURL: destinationURL, chunkSize: chunkSize, maxConcurrent: maxConcurrent)
        manager.setSpeedLimit(speedLimit)
        syncQueue.sync { managers[id] = manager }
        manager.start()
    }

    func resume(id: UUID) -> Bool {
        syncQueue.sync {
            guard let manager = managers[id] else { return false }
            manager.resume()
            return true
        }
    }

    func pause(id: UUID) {
        syncQueue.sync { managers[id]?.pause() }
    }

    func cancel(id: UUID) {
        syncQueue.sync {
            managers[id]?.cancel()
            managers.removeValue(forKey: id)
        }
    }

    func setSpeedLimit(id: UUID, limit: Int64) {
        syncQueue.sync { managers[id]?.setSpeedLimit(limit) }
    }

    func setMaxConcurrent(id: UUID, max: Int) {
        syncQueue.sync { managers[id]?.setMaxConcurrent(max) }
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
}
