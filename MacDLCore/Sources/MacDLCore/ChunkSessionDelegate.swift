import Foundation

// Routes URLSession delegate callbacks to the owning ChunkDownloadTask.
// All chunk tasks share ONE URLSession so HTTP/2 can multiplex streams on a
// single connection (and HTTP/1.1 reuses keep-alive connections) instead of
// opening a fresh TCP+TLS connection per chunk.
final class ChunkSessionDelegate: NSObject, URLSessionDataDelegate {
    private var tasks: [Int: ChunkDownloadTask] = [:]
    private let lock = NSLock()

    func register(_ task: ChunkDownloadTask, dataTask: URLSessionDataTask) {
        lock.lock()
        tasks[dataTask.taskIdentifier] = task
        lock.unlock()
    }

    func unregister(_ dataTask: URLSessionTask) {
        lock.lock()
        tasks.removeValue(forKey: dataTask.taskIdentifier)
        lock.unlock()
    }

    private func task(for dataTask: URLSessionTask) -> ChunkDownloadTask? {
        lock.lock()
        defer { lock.unlock() }
        return tasks[dataTask.taskIdentifier]
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let task = self.task(for: dataTask) else {
            completionHandler(.cancel)
            return
        }
        task.urlSession(session, dataTask: dataTask, didReceive: response, completionHandler: completionHandler)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let task = self.task(for: dataTask) else { return }
        task.urlSession(session, dataTask: dataTask, didReceive: data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let chunkTask = self.task(for: task) else { return }
        chunkTask.urlSession(session, task: task, didCompleteWithError: error)
        unregister(task)
    }
}
