import Foundation

final class DownloadTask: NSObject, URLSessionDownloadDelegate {
    let id: UUID
    let url: URL
    let destinationURL: URL
    var speedLimit: Int64 = 0
    var totalBytesExpected: Int64 = 0
    var totalBytesWritten: Int64 = 0
    var downloadSpeed: Int64 = 0

    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private(set) var resumeData: Data?
    private var startTime: Date?
    private var lastCheckBytes: Int64 = 0
    private var lastCheckTime: Date = .distantPast
    private var progressThrottleTime: Date = .distantPast
    private var speedSamples: [(Date, Int64)] = []

    var onProgress: ((Int64, Int64, Int64) -> Void)?
    var onCompletion: ((Result<Void, Error>) -> Void)?

    init(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64) {
        self.id = id
        self.url = url
        self.destinationURL = destinationURL
        self.speedLimit = speedLimit
    }

    func start() {
        session = makeSession()
        startTime = Date()
        lastCheckTime = Date()
        lastCheckBytes = 0
        speedSamples = [(Date(), 0)]
        task = session?.downloadTask(with: url)
        task?.resume()
    }

    func resume(from data: Data?) {
        totalBytesWritten = 0
        downloadSpeed = 0
        session = makeSession()
        startTime = Date()
        lastCheckTime = Date()
        lastCheckBytes = 0
        speedSamples = [(Date(), 0)]
        if let data {
            task = session?.downloadTask(withResumeData: data)
        } else {
            task = session?.downloadTask(with: url)
        }
        task?.resume()
        resumeData = nil
    }

    func pause() {
        task?.cancel { [weak self] data in
            guard let self else { return }
            self.resumeData = data
            self.session?.invalidateAndCancel()
            self.session = nil
        }
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
        session = nil
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 16
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 86400
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    // MARK: - URLSessionDownloadDelegate

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fm = FileManager.default
        let destDir = destinationURL.deletingLastPathComponent().path
        try? fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
        try? fm.removeItem(at: destinationURL)
        try? fm.moveItem(at: location, to: destinationURL)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError? {
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                if resumeData != nil { return }
            }
            onCompletion?(.failure(error))
        } else {
            onCompletion?(.success(()))
        }
        self.session?.invalidateAndCancel()
        self.session = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        self.totalBytesWritten = totalBytesWritten
        self.totalBytesExpected = max(totalBytesExpectedToWrite, self.totalBytesExpected)

        let now = Date()

        speedSamples.append((now, totalBytesWritten))
        if speedSamples.count > 6 { speedSamples.removeFirst() }
        if speedSamples.count >= 2 {
            let delta = totalBytesWritten - speedSamples.first!.1
            let elapsed = now.timeIntervalSince(speedSamples.first!.0)
            downloadSpeed = elapsed > 0 ? Int64(Double(delta) / elapsed) : 0
        }

        let elapsed = now.timeIntervalSince(lastCheckTime)
        if elapsed >= 0.5 {
            let instantSpeed = Int64(Double(totalBytesWritten - lastCheckBytes) / elapsed)
            if speedLimit > 0, instantSpeed > speedLimit {
                let ratio = Double(instantSpeed) / Double(speedLimit)
                let sleepTime = min(0.5 * (ratio - 1), 3.0)
                self.task?.suspend()
                DispatchQueue.global().asyncAfter(deadline: .now() + sleepTime) { [weak self] in
                    self?.task?.resume()
                }
            }
            lastCheckBytes = totalBytesWritten
            lastCheckTime = now
        }

        guard now.timeIntervalSince(progressThrottleTime) >= 0.2 else { return }
        progressThrottleTime = now
        onProgress?(totalBytesWritten, totalBytesExpected, downloadSpeed)
    }
}
