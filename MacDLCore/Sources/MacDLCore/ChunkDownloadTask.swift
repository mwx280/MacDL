import Foundation

/// One range request that streams bytes into a file handle at the throttle
/// rate. All chunk tasks share a single URLSession so HTTP/2 can multiplex.
/// @unchecked Sendable: mutable state is guarded by NSCondition/NSLock and the
/// delegate callbacks hop back to the owning queue.
public final class ChunkDownloadTask: NSObject, @unchecked Sendable {
    /// Returns the per-host connection cap used by the shared URLSession.
    /// Set once at app launch from the user's settings.
    public nonisolated(unsafe) static var maxConnectionsProvider: (() -> Int)?
    /// Test hook replacing the shared URLSession configuration.
    public nonisolated(unsafe) static var sessionConfigurationOverride: URLSessionConfiguration?
    /// Global token bucket shared by every download, capping the aggregate
    /// throughput across all tasks. Rate 0 = unlimited; the app sets it from the
    /// user's global speed-limit setting.
    public nonisolated static let globalBucket = TokenBucket(rate: 0)

    nonisolated static let sharedDelegate = ChunkSessionDelegate()
    nonisolated static let sharedSession: URLSession = {
        let config = sessionConfigurationOverride ?? URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = max(1, maxConnectionsProvider?() ?? 16)
        config.timeoutIntervalForRequest = EngineConstants.requestTimeout
        config.timeoutIntervalForResource = EngineConstants.resourceTimeout
        return URLSession(configuration: config, delegate: sharedDelegate, delegateQueue: nil)
    }()

    let chunkIndex: Int
    let url: URL
    let fileURL: URL
    let startOffset: Int64
    let endOffset: Int64
    let chunkSize: Int64
    private let chunkStartTime: Date

    private var dataTask: URLSessionDataTask?
    private var fileHandle: FileHandle?
    private(set) var bytesWritten: Int64 = 0
    private(set) var speed: Int64 = 0
    private(set) var isPaused = false
    private(set) var isCancelled = false
    private(set) var isCompleted = false
    // Set when the engine's stall watchdog cancels the task. Distinct from a
    // user cancel so the completion reports a retryable transport error instead
    // of .cancelled.
    private var stalled = false
    private var speedCheckTime: Date = .distantPast
    private var speedCheckBytes: Int64 = 0

    weak     var bucket: TokenBucket?
    var requestsWholeFile = false

    // didReceive fires on URLSession's delegate queue. Blocking it stalls the whole
    // transfer, so we only append to this buffer there and let a writer queue drain
    // it at the throttle rate (see drainLoop).
    private var pendingData = Data()
    // Guards pendingData and lets the writer sleep (instead of polling) until
    // data arrives or the response ends; the backpressure path waits on it too.
    private let dataCondition = NSCondition()
    private let finishLock = NSLock()
    private var writeScheduled = false
    private var responseComplete = false
    private var resumeOffset: Int64 = 0
    private let writerQueue = DispatchQueue(label: "com.xiaowu.chunkwriter")
    private let bufferCap = EngineConstants.chunkBufferCap
    private let writeChunk = EngineConstants.chunkWriteSize

    var onProgress: ((Int64) -> Void)?
    var onTotalSizeKnown: ((Int64) -> Void)?
    var onSupportsResume: ((Bool) -> Void)?
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
        resumeOffset = resumeFrom
        let from = startOffset + resumeFrom
        let to = endOffset - 1
        if !requestsWholeFile, resumeFrom >= endOffset - startOffset {
            // Whole chunk already downloaded (edge case): treat as success to avoid sending an invalid Range
            finish(with: .success(()))
            return
        }
        var req = URLRequest(url: url)
        if !requestsWholeFile {
            // Always send a bounded Range so resuming near the chunk end never omits it (which made the server return the whole 200 file)
            req.setValue("bytes=\(from)-\(to)", forHTTPHeaderField: "Range")
        }
        EngineLog.chunk.debug("Chunk #\(self.chunkIndex) start range=\(from)-\(to) resumeFrom=\(resumeFrom) wholeFile=\(self.requestsWholeFile ? 1 : 0)")

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let fh = FileHandle(forWritingAtPath: fileURL.path) else {
            finish(with: .failure(DownloadError.fileDeleted))
            return
        }
        fileHandle = fh
        // A whole-file (single-stream) task always starts at 0 and owns the file;
        // truncate so a retry never leaves stale bytes from a failed attempt behind.
        if requestsWholeFile {
            try? fh.truncate(atOffset: 0)
        }
        try? fh.seek(toOffset: UInt64(startOffset + resumeFrom))

        let task = Self.sharedSession.dataTask(with: req)
        Self.sharedDelegate.register(self, dataTask: task)
        dataTask = task
        task.resume()
    }

    func pause() {
        dataCondition.lock()
        isPaused = true
        dataCondition.broadcast()
        dataCondition.unlock()
        bucket?.stop()
        dataTask?.cancel()
        cleanup()
    }

    func cancel() {
        dataCondition.lock()
        isCancelled = true
        dataCondition.broadcast()
        dataCondition.unlock()
        bucket?.stop()
        dataTask?.cancel()
        cleanup()
    }

    /// Cancels the transfer as a stalled connection (no bytes for a while).
    /// The completion then surfaces a retryable network timeout so the engine
    /// re-dispatches the chunk instead of treating the cancel as a user action.
    func cancelAsStall() {
        dataCondition.lock()
        guard !stalled else { dataCondition.unlock(); return }
        stalled = true
        dataCondition.broadcast()
        dataCondition.unlock()
        dataTask?.cancel()
        cleanup()
    }

    private func cleanup() {
        // Run on the writer queue (not the main thread): synchronize() is an
        // fsync that can block for tens of milliseconds on a large write buffer,
        // and it must be serialized with the writer's file writes.
        writerQueue.async { [weak self] in
            guard let self else { return }
            if let fh = self.fileHandle {
                // The file may have been removed (user deleted it, test teardown)
                // between the handle being opened and this cleanup; synchronizeFile
                // would raise an NSException and crash the app.
                try? fh.synchronize()
                try? fh.close()
            }
            self.fileHandle = nil
        }
    }

    private func finish(with result: Result<Void, Error>) {
        // Reached from several paths (response, writer loop, early-range check);
        // the lock keeps it from firing twice.
        finishLock.lock()
        defer { finishLock.unlock() }
        guard !isCompleted else { return }
        isCompleted = true
        dataCondition.lock()
        dataCondition.broadcast()
        dataCondition.unlock()
        let elapsed = Date().timeIntervalSince(chunkStartTime)
        let resultStr = (try? result.get()) != nil ? "success" : "failure"
        EngineLog.chunk.notice("Chunk #\(self.chunkIndex) done size=\(self.bytesWritten) speed=\(self.speed)/s time=\(elapsed)s result=\(resultStr)")
        // Flush the exact final byte count even if the last write's progress
        // was throttled, so paused/resumed state is never stale.
        onProgress?(bytesWritten + resumeOffset)
        try? fileHandle?.close()
        fileHandle = nil
        DispatchQueue.main.async { [weak self] in
            self?.onCompletion?(result)
        }
    }
}

extension ChunkDownloadTask: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            // Non-HTTP response (e.g. FTP): the body is the whole file, delivered
            // with no Range support. Report the declared length when available.
            let expected = response.expectedContentLength
            if expected > 0 { onTotalSizeKnown?(expected) }
            onSupportsResume?(false)
            EngineLog.chunk.debug("Chunk #\(self.chunkIndex) non-HTTP response, expected=\(expected)")
            completionHandler(.allow)
            return
        }
        if http.statusCode == 416 {
            EngineLog.chunk.warning("Chunk #\(self.chunkIndex) 416 range not satisfiable, marking chunk failed")
            completionHandler(.cancel)
            finish(with: .failure(DownloadError.rangeNotSatisfiable))
            return
        }
        onSupportsResume?(http.statusCode == 206)
        switch http.statusCode {
        case 206:
            if let range = http.value(forHTTPHeaderField: "Content-Range"),
               let slash = range.lastIndex(of: "/") {
                let totalStr = String(range[range.index(after: slash)...]).trimmingCharacters(in: .whitespaces)
                if totalStr != "*", let total = Int64(totalStr), total > 0 {
                    onTotalSizeKnown?(total)
                } else {
                    EngineLog.chunk.warning("Chunk #\(self.chunkIndex) Content-Range size unparsable: \(range)")
                }
            }
        case 200..<300:
            // A bounded Range request answered with 200 means the server ignored
            // our Range header and is sending the whole file — writing it at this
            // chunk's offset would corrupt the download. (The single-stream task
            // with endOffset == Int64.max legitimately accepts a 200.)
            if !requestsWholeFile, endOffset != Int64.max {
                EngineLog.chunk.warning("Chunk #\(self.chunkIndex) server ignored Range (200), failing chunk")
                completionHandler(.cancel)
                finish(with: .failure(DownloadError.httpStatus(200)))
                return
            }
            let expected = response.expectedContentLength
            if expected > 0 { onTotalSizeKnown?(expected) }
        default:
            // Error responses (4xx/5xx) must not be treated as a valid file
            // size or written to the file. Fail the chunk so the engine can
            // retry (e.g. a 429 from a rate-limiting mirror).
            EngineLog.chunk.warning("Chunk #\(self.chunkIndex) HTTP \(http.statusCode), failing chunk")
            completionHandler(.cancel)
            finish(with: .failure(DownloadError.httpStatus(http.statusCode)))
            return
        }
        EngineLog.chunk.debug("Chunk #\(self.chunkIndex) response code=\((response as? HTTPURLResponse)?.statusCode ?? 0)")
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isCancelled, !isPaused, !stalled else { return }
        dataCondition.lock()
        pendingData.append(data)
        let overCap = pendingData.count > bufferCap
        dataCondition.signal()
        dataCondition.unlock()
        scheduleWrite()
        guard overCap else { return }
        // Buffer over its cap: wait (not poll) until the writer drains below it,
        // keeping memory bounded without a sleep loop.
        dataCondition.lock()
        while !isCancelled && !isPaused && !stalled && pendingData.count > bufferCap {
            dataCondition.wait()
        }
        dataCondition.unlock()
    }

    private func scheduleWrite() {
        dataCondition.lock()
        guard !writeScheduled else { dataCondition.unlock(); return }
        writeScheduled = true
        dataCondition.unlock()
        writerQueue.async { [weak self] in
            guard let self else { return }
            self.drainLoop()
            self.dataCondition.lock()
            self.writeScheduled = false
            self.dataCondition.unlock()
        }
    }

    private func drainLoop() {
        while true {
            dataCondition.lock()
            // Sleep until data arrives or the response ends — no polling.
            while pendingData.isEmpty && !isCancelled && !isPaused && !isCompleted && !responseComplete && !stalled {
                dataCondition.wait()
            }
            if isCancelled || isPaused || isCompleted || stalled {
                dataCondition.unlock()
                return
            }
            let chunk: Data?
            if pendingData.isEmpty {
                chunk = nil
            } else {
                let n = min(pendingData.count, writeChunk)
                chunk = pendingData.prefix(n)
                pendingData.removeFirst(n)
            }
            let done = responseComplete
            dataCondition.unlock()

            if let c = chunk {
                if bucket?.take(Double(c.count)) == false { return }
                // The global bucket caps the aggregate throughput across all
                // downloads; it is shared and only throttles when a global limit
                // is set (rate > 0).
                if Self.globalBucket.take(Double(c.count)) == false { return }
                if isCancelled || isPaused || isCompleted || stalled { return }
                guard let fh = fileHandle else { return }
                fh.write(c)
                bytesWritten += Int64(c.count)
                let now = Date()
                if speedCheckTime == .distantPast {
                    speedCheckTime = now
                    speedCheckBytes = bytesWritten
                }
                let elapsed = now.timeIntervalSince(speedCheckTime)
                if elapsed >= EngineConstants.speedSampleInterval {
                    speed = Int64(Double(bytesWritten - speedCheckBytes) / elapsed)
                    speedCheckTime = now
                    speedCheckBytes = bytesWritten
                    // Report progress at the same cadence as speed so fast
                    // downloads don't flood the main thread with a callback
                    // per 64 KB write.
                    onProgress?(bytesWritten + resumeOffset)
                }
                // Wake any backpressure waiter now that the buffer has room.
                dataCondition.lock()
                dataCondition.broadcast()
                dataCondition.unlock()
            } else {
                if done {
                    finish(with: .success(()))
                }
                return
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError? {
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                // A pause cancels the task on purpose - treat it as a clean stop, not an error.
                if isPaused {
                    dataCondition.lock()
                    responseComplete = true
                    dataCondition.broadcast()
                    dataCondition.unlock()
                    return
                }
                if stalled {
                    // The stall watchdog cancelled the task: surface a retryable
                    // transport error so the engine retries the chunk.
                    finish(with: .failure(DownloadError.network(URLError(.timedOut))))
                } else {
                    finish(with: .failure(DownloadError.cancelled))
                }
            } else {
                finish(with: .failure(error))
            }
            dataCondition.lock()
            responseComplete = true
            dataCondition.broadcast()
            dataCondition.unlock()
        } else {
            dataCondition.lock()
            responseComplete = true
            dataCondition.broadcast()
            dataCondition.unlock()
            scheduleWrite()
        }
    }
}
