import Foundation

final class DownloadTask: NSObject {

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
    private var task: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private var lastCheckBytes: Int64 = 0
    private var lastCheckTime: Date = .distantPast
    private var progressThrottleTime: Date = .distantPast
    private var speedSamples: [(Date, Int64)] = []
    private var isSuspended = false
    private var isPaused = false
    private var isCompleted = false

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

    deinit {
        fileHandle?.closeFile()
    }

    // MARK: - Public control方法
    func start() {
        #if DEBUG
        let previewNames: Set<String> = ["file.zip", "Xcode_26.6.xip", "Xcode.xip"]
        if previewNames.contains(destinationURL.lastPathComponent) {
            assertionFailure("Attempted to create preview file: \(destinationURL.lastPathComponent)")
        }
        #endif
        session = makeSession()
        let fileSize = ((try? FileManager.default.attributesOfItem(atPath: destinationURL.path))?[.size] as? Int64) ?? 0
        if fileSize > 0 {
            fileHandle = FileHandle(forWritingAtPath: destinationURL.path)
            fileHandle?.seekToEndOfFile()
            totalBytesWritten = fileSize
            lastCheckTime = Date()
            lastCheckBytes = fileSize
            speedSamples = [(Date(), fileSize)]
            var req = URLRequest(url: url)
            req.setValue("bytes=\(fileSize)-", forHTTPHeaderField: "Range")
            task = session?.dataTask(with: req)
        } else {
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
            fileHandle = FileHandle(forWritingAtPath: destinationURL.path)
            lastCheckTime = Date()
            lastCheckBytes = 0
            speedSamples = [(Date(), 0)]
            task = session?.dataTask(with: url)
        }
        task?.resume()
    }

    func resume(from offset: Int64) {
        session = makeSession()
        let fileSize = ((try? FileManager.default.attributesOfItem(atPath: destinationURL.path))?[.size] as? Int64) ?? 0
        let actualOffset: Int64
        if fileSize > 0 && fileSize == offset {
            actualOffset = offset
            fileHandle = FileHandle(forWritingAtPath: destinationURL.path)
            fileHandle?.seekToEndOfFile()
        } else {
            actualOffset = 0
            try? FileManager.default.removeItem(at: destinationURL)
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
            fileHandle = FileHandle(forWritingAtPath: destinationURL.path)
        }
        totalBytesWritten = actualOffset
        lastCheckTime = Date()
        lastCheckBytes = actualOffset
        speedSamples = [(Date(), actualOffset)]

        var req = URLRequest(url: url)
        if actualOffset > 0 {
            req.setValue("bytes=\(actualOffset)-", forHTTPHeaderField: "Range")
        }
        task = session?.dataTask(with: req)
        task?.resume()
        isPaused = false
    }

    func pause() {
        isPaused = true
        task?.cancel()
        fileHandle?.synchronizeFile()
        fileHandle?.closeFile()
        fileHandle = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func cancel() {
        isPaused = false
        task?.cancel()
        fileHandle?.closeFile()
        fileHandle = nil
        session?.invalidateAndCancel()
        session = nil
        try? FileManager.default.removeItem(at: destinationURL)
    }

    // MARK: - Internal helpers
    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 16
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 86400
        return URLSession(configuration: config, delegate: self, delegateQueue: .main)
    }

    private func finish(with result: Result<Void, Error>) {
        guard !isCompleted else { return }
        isCompleted = true
        fileHandle?.closeFile()
        fileHandle = nil
        onCompletion?(result)
    }

    private func appendData(_ data: Data) {
        fileHandle?.write(data)
        totalBytesWritten += Int64(data.count)
    }
}

// MARK: - URLSessionDataDelegate
extension DownloadTask: URLSessionDataDelegate {

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, http.statusCode == 200, totalBytesWritten > 0 {
            try? FileManager.default.removeItem(at: destinationURL)
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)
            fileHandle = FileHandle(forWritingAtPath: destinationURL.path)
            totalBytesWritten = 0
            totalBytesExpected = 0
            lastCheckBytes = 0
            speedSamples = [(Date(), 0)]
        }
        if totalBytesExpected == 0 {
            totalBytesExpected = response.expectedContentLength > 0 ? response.expectedContentLength : 0
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        appendData(data)

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
            if !FileManager.default.fileExists(atPath: destinationURL.path) {
                finish(with: .failure(DownloadError.fileDeleted))
                task?.cancel()
                return
            }
            let instantSpeed = Int64(Double(totalBytesWritten - lastCheckBytes) / elapsed)
            if speedLimit > 0, instantSpeed > speedLimit, !isSuspended {
                let ratio = Double(instantSpeed) / Double(speedLimit)
                let sleepTime = min(0.5 * (ratio - 1), 3.0)
                isSuspended = true
                task?.suspend()
                DispatchQueue.main.asyncAfter(deadline: .now() + sleepTime) { [weak self] in
                    self?.task?.resume()
                    self?.isSuspended = false
                }
            }
            lastCheckBytes = totalBytesWritten
            lastCheckTime = now
        }

        guard now.timeIntervalSince(progressThrottleTime) >= 0.2 else { return }
        progressThrottleTime = now
        onProgress?(totalBytesWritten, totalBytesExpected, downloadSpeed)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError? {
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                if isPaused { return }
                finish(with: .failure(DownloadError.cancelled))
            } else {
                finish(with: .failure(error))
            }
        } else {
            finish(with: .success(()))
        }
        self.session?.invalidateAndCancel()
        self.session = nil
    }
}

// MARK: - Custom errors
enum DownloadError: Error, LocalizedError {
    case cancelled
    case fileDeleted
    var errorDescription: String? {
        switch self {
        case .cancelled: return "下载已取消"
        case .fileDeleted: return "下载文件已被删除"
        }
    }
}
