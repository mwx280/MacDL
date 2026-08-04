import Foundation

public final class ChunkDownloadTask: NSObject {
    public nonisolated(unsafe) static var maxConnectionsProvider: (() -> Int)?
    public nonisolated(unsafe) static var sessionConfigurationOverride: URLSessionConfiguration?

    nonisolated(unsafe) static let sharedDelegate = ChunkSessionDelegate()
    nonisolated(unsafe) static let sharedSession: URLSession = {
        let config = sessionConfigurationOverride ?? URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = max(1, maxConnectionsProvider?() ?? 8)
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
    private var speedCheckTime: Date = .distantPast
    private var speedCheckBytes: Int64 = 0

    weak     var bucket: TokenBucket?
    var requestsWholeFile = false

    // didReceive fires on URLSession's delegate queue. Blocking it stalls the whole
    // transfer, so we only append to this buffer there and let a writer queue drain
    // it at the throttle rate (see drainLoop).
    private var pendingData = Data()
    private let dataLock = NSLock()
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
        try? fh.seek(toOffset: UInt64(startOffset + resumeFrom))

        let task = Self.sharedSession.dataTask(with: req)
        Self.sharedDelegate.register(self, dataTask: task)
        dataTask = task
        task.resume()
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
        }
    }

    private func finish(with result: Result<Void, Error>) {
        // Reached from several paths (response, writer loop, early-range check);
        // the lock keeps it from firing twice.
        finishLock.lock()
        defer { finishLock.unlock() }
        guard !isCompleted else { return }
        isCompleted = true
        let elapsed = Date().timeIntervalSince(chunkStartTime)
        let speed = elapsed > 0 ? Int64(Double(bytesWritten) / elapsed) : bytesWritten
        let resultStr = (try? result.get()) != nil ? "success" : "failure"
        EngineLog.chunk.notice("Chunk #\(self.chunkIndex) done size=\(self.bytesWritten) speed=\(self.speed)/s time=\(elapsed)s result=\(resultStr)")
        // Flush the exact final byte count even if the last write's progress
        // was throttled, so paused/resumed state is never stale.
        onProgress?(bytesWritten + resumeOffset)
        fileHandle?.closeFile()
        fileHandle = nil
        DispatchQueue.main.async { [weak self] in
            self?.onCompletion?(result)
        }
    }
}

extension ChunkDownloadTask: URLSessionDataDelegate {
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse, http.statusCode == 416 {
            EngineLog.chunk.warning("Chunk #\(self.chunkIndex) 416 range not satisfiable, marking chunk failed")
            completionHandler(.cancel)
            finish(with: .failure(DownloadError.rangeNotSatisfiable))
            return
        }
        if let http = response as? HTTPURLResponse {
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
        }
        EngineLog.chunk.debug("Chunk #\(self.chunkIndex) response code=\((response as? HTTPURLResponse)?.statusCode ?? 0)")
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isCancelled, !isPaused else { return }
        dataLock.lock()
        pendingData.append(data)
        let overCap = pendingData.count > bufferCap
        dataLock.unlock()
        scheduleWrite()
        guard overCap else { return }
        // Buffer over its cap: block briefly as backpressure to keep memory bounded on large files
        while true {
            if isCancelled || isPaused { return }
            dataLock.lock()
            let big = pendingData.count > bufferCap
            dataLock.unlock()
            if !big { break }
            Thread.sleep(forTimeInterval: EngineConstants.drainPollInterval)
        }
    }

    private func scheduleWrite() {
        dataLock.lock()
        guard !writeScheduled else { dataLock.unlock(); return }
        writeScheduled = true
        dataLock.unlock()
        writerQueue.async { [weak self] in
            guard let self else { return }
            self.drainLoop()
            self.dataLock.lock()
            self.writeScheduled = false
            self.dataLock.unlock()
        }
    }

    private func drainLoop() {
        while true {
            if isCancelled || isPaused || isCompleted { return }
            dataLock.lock()
            let chunk: Data?
            if pendingData.isEmpty {
                chunk = nil
            } else {
                let n = min(pendingData.count, writeChunk)
                chunk = pendingData.prefix(n)
                pendingData.removeFirst(n)
            }
            let done = responseComplete
            dataLock.unlock()

            if let c = chunk {
                if bucket?.take(Double(c.count)) == false { return }
                if isCancelled || isPaused || isCompleted { return }
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
            } else {
                if done {
                    finish(with: .success(()))
                    return
                }
                Thread.sleep(forTimeInterval: EngineConstants.drainPollInterval)
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error as NSError? {
            if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
                // A pause cancels the task on purpose - treat it as a clean stop, not an error.
                if isPaused {
                    dataLock.lock()
                    responseComplete = true
                    dataLock.unlock()
                    return
                }
                finish(with: .failure(DownloadError.cancelled))
            } else {
                finish(with: .failure(error))
            }
            dataLock.lock()
            responseComplete = true
            dataLock.unlock()
        } else {
            dataLock.lock()
            responseComplete = true
            dataLock.unlock()
            scheduleWrite()
        }
    }
}
