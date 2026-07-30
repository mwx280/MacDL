import Foundation

final class DownloadEngine {
    static let shared = DownloadEngine()

    private var tasks: [UUID: DownloadTask] = [:]

    private init() {}

    func start(url: URL, destinationURL: URL, speedLimit: Int64) -> UUID {
        let id = UUID()
        let task = DownloadTask(id: id, url: url, destinationURL: destinationURL, speedLimit: speedLimit)
        tasks[id] = task
        task.start()
        return id
    }

    func pause(id: UUID) {
        tasks[id]?.pause()
    }

    func cancel(id: UUID) {
        tasks[id]?.cancel()
        tasks.removeValue(forKey: id)
    }

    func setSpeedLimit(id: UUID, limit: Int64) {
        tasks[id]?.speedLimit = limit
    }

    func setProgressHandler(for id: UUID, handler: @escaping (Int64, Int64, Int64) -> Void) {
        tasks[id]?.onProgress = handler
    }

    func setCompletionHandler(for id: UUID, handler: @escaping (Result<Void, Error>) -> Void) {
        tasks[id]?.onCompletion = handler
    }

    func setResumeDataHandler(for id: UUID, handler: @escaping (Data?) -> Void) {
        tasks[id]?.onResumeData = handler
    }
}
