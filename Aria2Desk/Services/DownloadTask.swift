import Foundation

final class DownloadTask: NSObject, URLSessionDownloadDelegate {

    // MARK: - Public properties
    let id: UUID
    let url: URL
    let destinationURL: URL
    var speedLimit: Int64 = 0
    var totalBytesExpected: Int64 = 0
    var totalBytesWritten: Int64 = 0
    var downloadSpeed: Int64 = 0

    // MARK: - Private state
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private(set) var resumeData: Data?
    private var lastCheckBytes: Int64 = 0
    private var lastCheckTime: Date = .distantPast
    private var progressThrottleTime: Date = .distantPast
    private var speedSamples: [(Date, Int64)] = []
    private var isSuspended = false
    private var isPaused = false
    private var isCompleted = false          // Prevent the completion callback from firing twice

    // MARK: - Callbacks
    var onProgress: ((Int64, Int64, Int64) -> Void)?
    var onCompletion: ((Result<Void, Error>) -> Void)?

    // MARK: - Initialization
    init(id: UUID, url: URL, destinationURL: URL, speedLimit: Int64) {
        self.id = id
        self.url = url
        self.destinationURL = destinationURL
        self.speedLimit = speedLimit
    }

    // MARK: - Public control方法
    func start() {
        session = makeSession()
        lastCheckTime = Date()
        lastCheckBytes = 0
        speedSamples = [(Date(), 0)]
        task = session?.downloadTask(with: url)
        task?.resume()
    }

    func resume(from data: Data?) {
        session = makeSession()
        lastCheckTime = Date()
        lastCheckBytes = totalBytesWritten
        speedSamples = [(Date(), totalBytesWritten)]
        if let data {
            task = session?.downloadTask(withResumeData: data)
        } else {
            task = session?.downloadTask(with: url)
        }
        task?.resume()
        resumeData = nil
        isPaused = false
    }

    func pause() {
        isPaused = true
        task?.cancel { [weak self] data in
            guard let self else { return }
            // Extract the real downloaded byte count from resumeData so it stays consistent with the system
            if let data = data {
                self.resumeData = data
                if let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let received = dict["NSURLSessionResumeBytesReceived"] as? Int64 {
                    self.totalBytesWritten = received
                }
            }
            self.session?.invalidateAndCancel()
            self.session = nil
        }
    }

    func cancel() {
        // A cancel isn't a pause; mark as not paused
        isPaused = false
        task?.cancel()
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - Internal helpers
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 16
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 86400
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    /// Single completion callback, guaranteed to fire once
    private func finish(with result: Result<Void, Error>) {
        guard !isCompleted else { return }
        isCompleted = true
        onCompletion?(result)
    }

    // MARK: - URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let fm = FileManager.default
        let destDir = destinationURL.deletingLastPathComponent().path
        do {
            try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
            // Remove the target file first if it already exists
            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }
            try fm.moveItem(at: location, to: destinationURL)
        } catch {
            finish(with: .failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError? {
            // Two ways a cancel is handled
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                if isPaused {
                    // Cancel from a pause: no completion callback, no invalidate (already handled in pause)
                    return
                } else {
                    // User-initiated cancel, report failure
                    finish(with: .failure(DownloadError.cancelled))
                }
            } else {
                // A real network error
                finish(with: .failure(error))
            }
        } else {
            // No error, normal completion
            finish(with: .success(()))
        }
        // Clean up the session when the task finishes
        self.session?.invalidateAndCancel()
        self.session = nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        self.totalBytesWritten = totalBytesWritten
        if totalBytesExpectedToWrite > 0 {
            self.totalBytesExpected = max(totalBytesExpectedToWrite, self.totalBytesExpected)
        }

        let now = Date()

        // Update the speed sample
        speedSamples.append((now, totalBytesWritten))
        if speedSamples.count > 6 { speedSamples.removeFirst() }
        if speedSamples.count >= 2 {
            let delta = totalBytesWritten - speedSamples.first!.1
            let elapsed = now.timeIntervalSince(speedSamples.first!.0)
            downloadSpeed = elapsed > 0 ? Int64(Double(delta) / elapsed) : 0
        }

        // Throttle control
        let elapsed = now.timeIntervalSince(lastCheckTime)
        if elapsed >= 0.5 {
            let instantSpeed = Int64(Double(totalBytesWritten - lastCheckBytes) / elapsed)
            if speedLimit > 0, instantSpeed > speedLimit, !isSuspended {
                let ratio = Double(instantSpeed) / Double(speedLimit)
                let sleepTime = min(0.5 * (ratio - 1), 3.0)
                isSuspended = true
                self.task?.suspend()
                DispatchQueue.main.asyncAfter(deadline: .now() + sleepTime) { [weak self] in
                    self?.task?.resume()
                    self?.isSuspended = false
                }
            }
            lastCheckBytes = totalBytesWritten
            lastCheckTime = now
        }

        // Throttle the progress callback
        guard now.timeIntervalSince(progressThrottleTime) >= 0.2 else { return }
        progressThrottleTime = now
        onProgress?(totalBytesWritten, totalBytesExpected, downloadSpeed)
    }
}

// MARK: - Custom errors
enum DownloadError: Error, LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled: return "下载已取消"
        }
    }
}
