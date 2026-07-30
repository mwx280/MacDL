import Foundation

final class DownloadEngine {

    static let shared = DownloadEngine()

    private var tasks: [UUID: DownloadTask] = [:]
    private let syncQueue = DispatchQueue(label: "com.xiaowu.downloadengine.sync")

    private init() {}

    // MARK: - Public interface
    func start(url: URL, destinationURL: URL, speedLimit: Int64) -> UUID {
        let id = UUID()
        let task = DownloadTask(id: id, url: url, destinationURL: destinationURL, speedLimit: speedLimit)
        syncQueue.sync { tasks[id] = task }
        task.start()
        return id
    }

    func resume(id: UUID) -> Bool {
        syncQueue.sync {
            guard let task = tasks[id], let data = task.resumeData else { return false }
            task.resume(from: data)
            return true
        }
    }

    func pause(id: UUID) {
        syncQueue.sync { tasks[id]?.pause() }
    }

    func cancel(id: UUID) {
        syncQueue.sync {
            tasks[id]?.cancel()
            tasks.removeValue(forKey: id)
        }
    }

    func setSpeedLimit(id: UUID, limit: Int64) {
        syncQueue.sync { tasks[id]?.speedLimit = limit }
    }

    func setProgressHandler(for id: UUID, handler: @escaping (Int64, Int64, Int64) -> Void) {
        syncQueue.sync { tasks[id]?.onProgress = handler }
    }

    func setCompletionHandler(for id: UUID, handler: @escaping (Result<Void, Error>) -> Void) {
        syncQueue.sync {
            tasks[id]?.onCompletion = { [weak self] result in
                handler(result)
                self?.syncQueue.async {
                    self?.tasks.removeValue(forKey: id)
                }
            }
        }
    }
}
