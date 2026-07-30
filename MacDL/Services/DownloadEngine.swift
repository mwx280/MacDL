import Foundation

final class DownloadEngine {

    static let shared = DownloadEngine()

    private var tasks: [UUID: DownloadTask] = [:]
    private let syncQueue = DispatchQueue(label: "com.xiaowu.downloadengine.sync")

    private init() {}

    // MARK: - Public interface
    func start(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64, resumeFrom: Int64 = 0) {
        let task = DownloadTask(id: id, url: url, destinationURL: destinationURL, speedLimit: speedLimit)
        syncQueue.sync { tasks[id] = task }
        if resumeFrom > 0 {
            task.resume(from: resumeFrom)
        } else {
            task.start()
        }
    }

    func resume(id: UUID) -> Bool {
        syncQueue.sync {
            guard let task = tasks[id] else { return false }
            task.resume(from: task.totalBytesWritten)
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

    var hasActiveTasks: Bool {
        syncQueue.sync { !tasks.isEmpty }
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
