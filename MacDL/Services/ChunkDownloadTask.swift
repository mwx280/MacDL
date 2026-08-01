import Foundation
import os

final class ChunkDownloadTask: NSObject {
    let chunkIndex: Int
    let url: URL
    let fileURL: URL
    let startOffset: Int64
    let endOffset: Int64
    let chunkSize: Int64
    private let chunkStartTime: Date

    private var session: URLSession?
    private var dataTask: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private(set) var bytesWritten: Int64 = 0
    private(set) var speed: Int64 = 0
    private(set) var isPaused = false
    private(set) var isCancelled = false
    private(set) var isCompleted = false
    private var speedCheckTime: Date = .distantPast
    private var speedCheckBytes: Int64 = 0

    var bucket: TokenBucket?

    var onProgress: ((Int64) -> Void)?
    var onTotalSizeKnown: ((Int64) -> Void)?
    var onCompletion: ((Result<Void, Error>) -> Void)?

    init(chunkIndex: Int, url: URL, fileURL: URL, startOffset: Int64, endOffset: Int64) {
        self.chunkIndex = chunkIndex
        self.url = url
        self.fileURL = fileURL
        self.startOffset = startOffset
        self.endOffset = endOffset
        chunkSize = endOffset - startOffset
        chunkStartTime = Date()
    }
    deinit {
        fileHandle?.closeFile()
    }

    func start(resumeFrom: Int64 = 0) {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = max(1, SettingsStore.shared.maxConnections)
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 86400
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)

        let from = startOffset + resumeFrom
        let to = endOffset - 1
        var req = URLRequest(url: url)
        if from < to {
            req.setValue("bytes=\(from)-\(to)", forHTTPHeaderField: "Range")
        } else if from == startOffset {
            req.setValue("bytes=\(startOffset)-\(to)", forHTTPHeaderField: "Range")
        }
        os_log("[Chunk #%d] start range=%lld-%lld resumeFrom=%lld", chunkIndex, from, to, resumeFrom)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let fh = FileHandle(forWritingAtPath: fileURL.path) else {
            session?.invalidateAndCancel()
            session = nil
            finish(with: .failure(DownloadError.fileDeleted))
            return
        }
        fileHandle = fh
        try? fh.seek(toOffset: UInt64(startOffset + resumeFrom))

        dataTask = session?.dataTask(with: req)
        dataTask?.resume()
    }

    func pause() {
        isPaused = true
        bucket?.stop()
        dataTask?.cancel()
        cleanup()
    }

    func cancel() {
        isCancelled = true
        bucket?.stop()
        dataTask?.cancel()
        cleanup()
    }

    private func cleanup() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fileHandle?.synchronizeFile()
            self.fileHandle?.closeFile()
            self.fileHandle = nil
            self.session?.invalidateAndCancel()
            self.session = nil
        }
    }

    private func finish(with result: Result<Void, Error>) {
        guard !isCompleted else { return }
        isCompleted = true
        let elapsed = Date().timeIntervalSince(chunkStartTime)
        let speed = elapsed > 0 ? Int64(Double(bytesWritten) / elapsed) : bytesWritten
        let resultStr = (try? result.get()) != nil ? "success" : "failure"
        os_log("[Chunk #%d] done size=%lld speed=%lld/s time=%.2fs result=%{public}@",
               chunkIndex, bytesWritten, speed, elapsed, resultStr)
        fileHandle?.closeFile()
        fileHandle = nil
        DispatchQueue.main.async { [weak self] in
            self?.onCompletion?(result)
        }
    }
}

extension ChunkDownloadTask: URLSessionDataDelegate {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, http.statusCode == 416 {
            os_log("[Chunk #%d] 416 range not satisfiable, marking chunk failed (restart from scratch required)", chunkIndex)
            try? FileManager.default.removeItem(at: fileURL)
            completionHandler(.cancel)
            finish(with: .failure(DownloadError.rangeNotSatisfiable))
            return
        }
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 206 {
                if let range = http.allHeaderFields["Content-Range"] as? String,
                   let slash = range.lastIndex(of: "/") {
                    let totalStr = range[range.index(after: slash)...].trimmingCharacters(in: .whitespaces)
                    if let total = Int64(totalStr), total > 0 {
                        onTotalSizeKnown?(total)
                    }
                }
            } else {
                let expected = response.expectedContentLength
                if expected > 0 { onTotalSizeKnown?(expected) }
            }
        }
        os_log("[Chunk #%d] response code=%d", chunkIndex, (response as? HTTPURLResponse)?.statusCode ?? 0)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isCancelled else { return }
        guard bucket?.take(Double(data.count)) != false else { return }
        fileHandle?.write(data)
        bytesWritten += Int64(data.count)
        if speedCheckTime == .distantPast {
            speedCheckTime = Date()
            speedCheckBytes = bytesWritten
        }
        let now = Date()
        let elapsed = now.timeIntervalSince(speedCheckTime)
        if elapsed >= 0.3 {
            speed = Int64(Double(bytesWritten - speedCheckBytes) / elapsed)
            speedCheckTime = now
            speedCheckBytes = bytesWritten
        }
        onProgress?(bytesWritten)
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
        session.invalidateAndCancel()
        self.session = nil
    }
}
