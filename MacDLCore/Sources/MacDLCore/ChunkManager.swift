import Foundation

// All mutable state lives on syncQueue. Every callback re-enters through
// syncQueue.async, so nothing is ever touched from two threads at once.
public final class ChunkManager {
    public let id: UUID
    public let url: URL
    public let destinationURL: URL
    public private(set) var chunkSize: Int64
    public private(set) var totalSize: Int64 = 0
    public private(set) var downloadSpeed: Int64 = 0

    private var maxConcurrent: Int
    private var speedLimit: Int64 = 0
    private var chunks: [Chunk] = []
    private var activeTasks: [Int: ChunkDownloadTask] = [:]
    private var pendingIndices: [Int] = []
    private var retryCounts: [Int: Int] = [:]
    private var lastError: Error?
    private var serverSupportsResume: Bool?
    private var singleStreamMode = false
    private var singleStreamTask: ChunkDownloadTask?
    private var singleStreamTotal: Int64 = 0
    private var singleStreamBytes: Int64 = 0

    private let maxRetries = EngineConstants.maxChunkRetries
    private let bucket = TokenBucket(rate: 0)

    private let syncQueue = DispatchQueue(label: "com.xiaowu.chunkmanager.sync")
    private var logTimer: Timer?
    private var lastLogBytes: Int64 = 0
    private var lastLogTime: Date = .distantPast
    private var lastChunksChangedTime: Date = .distantPast
    private var pendingChunksChanged = false

    public var onProgress: ((Int64, Int64, Int64) -> Void)?
    public var onChunksChanged: (([Chunk]) -> Void)?
    public var onCompletion: ((Result<Void, Error>) -> Void)?
    public var onResumeSupport: ((Bool) -> Void)?

    public init(id: UUID, url: URL, destinationURL: URL, chunkSize: Int64, maxConcurrent: Int) {
        self.id = id
        self.url = url
        self.destinationURL = destinationURL
        self.chunkSize = chunkSize
        self.maxConcurrent = maxConcurrent
    }

    // MARK: - Public control

    public func start() {
        EngineLog.manager.notice("start probe chunkSize=\(self.chunkSize) maxConcurrent=\(self.maxConcurrent)")
        startLogTimer()
        syncQueue.async { self.startProbe() }
    }

    public func start(withChunks existing: [Chunk], totalSize: Int64) {
        EngineLog.manager.notice("resume chunks=\(existing.count) pending=\(existing.filter { $0.status != .completed }.count) completed=\(existing.filter { $0.status == .completed }.count) total=\(totalSize)")
        startLogTimer()
        syncQueue.async {
            self.totalSize = totalSize
            self.chunks = existing
            for i in self.chunks.indices where self.chunks[i].status != .completed {
                self.chunks[i].status = .pending
            }
            self.pendingIndices = self.chunks.filter { $0.status == .pending }.map(\.index)
            self.updateBucket()
            self.dispatchNext()
        }
    }

    private func startProbe() {
        updateBucket()
        // The first request is a probe: one chunk with a Range header. It reveals the
        // total size (via Content-Range) and whether the server honors 206 at all;
        // the rest of the file gets chunked only after that.
        let probe = Chunk(index: 0, startOffset: 0, endOffset: chunkSize, downloadedSize: 0, status: .downloading)
        chunks = [probe]
        let task = ChunkDownloadTask(chunkIndex: 0, url: url, fileURL: destinationURL, startOffset: 0, endOffset: chunkSize)
        task.bucket = bucket
        setupTask(task, index: 0)
        task.onTotalSizeKnown = { [weak self] total in
            guard let self else { return }
            self.syncQueue.async {
                guard total > 0 else { return }
                self.totalSize = total
                EngineLog.manager.notice("totalSize=\(total)")
                guard !self.singleStreamMode else { return }
                let built = self.buildChunks(totalSize: total, chunkSize: self.chunkSize)
                self.chunks = built
                self.chunks[0].status = .downloading
                self.chunks[0].downloadedSize = 0
                self.pendingIndices = Array(1..<built.count)
                self.notifyChunksChanged(force: true)
                self.dispatchNext()
            }
        }
        activeTasks[0] = task
        task.start(resumeFrom: 0)
    }

    private func setupTask(_ task: ChunkDownloadTask, index: Int) {
        task.onProgress = { [weak self] bytes in
            guard let self else { return }
            self.syncQueue.async {
                guard index < self.chunks.count else { return }
                self.chunks[index].downloadedSize = bytes
                self.updateProgress()
            }
        }
        task.onSupportsResume = { [weak self] value in
            guard let self else { return }
            self.syncQueue.async {
                guard self.serverSupportsResume == nil else { return }
                self.serverSupportsResume = value
                self.onResumeSupport?(value)
                if !value {
                    self.enterSingleStream()
                }
            }
        }
        task.onTotalSizeKnown = { [weak self] total in
            guard let self else { return }
            self.syncQueue.async {
                // Resume: the server file size doesn't match the persisted total, so safe resume isn't possible
                guard total > 0, self.totalSize > 0, total != self.totalSize else { return }
                EngineLog.manager.error("server total=\(total) differs from \(self.totalSize), abort resume")
                self.lastError = DownloadError.fileChanged
                for (_, t) in self.activeTasks { t.cancel() }
                self.activeTasks.removeAll()
                self.pendingIndices.removeAll()
                self.logTimer?.invalidate()
                self.logTimer = nil
                self.onCompletion?(.failure(DownloadError.fileChanged))
            }
        }
        task.onCompletion = { [weak self] result in
            guard let self else { return }
            self.syncQueue.async {
                self.activeTasks.removeValue(forKey: index)
                switch result {
                case .success:
                    guard index < self.chunks.count else { return }
                    self.chunks[index].status = .completed
                    self.chunks[index].downloadedSize = self.chunks[index].size
                    self.retryCounts[index] = nil
                    EngineLog.manager.notice("chunk \(index) completed")
                    if self.totalSize == 0, self.chunks.count == 1, !self.singleStreamMode {
                        EngineLog.manager.notice("probe completed without file size, falling back to single-stream")
                        self.enterSingleStream()
                        return
                    }
                case .failure(let error):
                    self.handleChunkFailure(index, error: error)
                }
                self.updateProgress()
                self.notifyChunksChanged()
                self.checkDone()
                self.dispatchNext()
            }
        }
    }

    private func handleChunkFailure(_ index: Int, error: Error) {
        guard index < chunks.count else { return }
        if let dlError = error as? DownloadError, !dlError.isRetryable {
            lastError = error
            chunks[index].status = .failed
            EngineLog.manager.error("chunk \(index) failed permanently (\(dlError.errorDescription ?? "?"))")
            return
        }
        let attempt = (retryCounts[index] ?? 0) + 1
        guard attempt <= maxRetries else {
            lastError = error
            chunks[index].status = .failed
            EngineLog.manager.error("chunk \(index) failed permanently after \(self.maxRetries) attempts")
            return
        }
        retryCounts[index] = attempt
        chunks[index].status = .pending
        pendingIndices.append(index)
        pendingIndices.sort()
        // Exponential backoff: 1s, 2s, 4s... capped at 10s.
        let delay = min(EngineConstants.retryBackoffBase * pow(2.0, Double(attempt - 1)), EngineConstants.retryBackoffCap)
        EngineLog.manager.warning("chunk \(index) failed, retry \(attempt)/\(self.maxRetries) in \(delay)s")
        syncQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.dispatchNext()
        }
    }

    public func setSpeedLimit(_ limit: Int64) {
        EngineLog.manager.notice("speedLimit=\(limit)/s")
        syncQueue.async {
            self.speedLimit = limit
            self.updateBucket()
        }
    }

    public func setMaxConcurrent(_ max: Int) {
        maxConcurrent = max
        EngineLog.manager.notice("maxConcurrent=\(max)")
        syncQueue.async { self.dispatchNext() }
    }

    public func pause() {
        EngineLog.manager.notice("pause")
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.logTimer?.invalidate()
            self.logTimer = nil
            self.bucket.stop()
            for (_, task) in self.activeTasks { task.pause() }
            self.activeTasks.removeAll()
            self.singleStreamTask?.pause()
            self.singleStreamTask = nil
        }
    }

    public func resume() {
        EngineLog.manager.notice("resume")
        startLogTimer()
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.bucket.reset(rate: self.speedLimit > 0 ? Double(self.speedLimit) : 0)
            if self.singleStreamMode {
                self.enterSingleStream()
            } else {
                // pause() clears activeTasks, orphaning in-flight (.downloading) chunks;
                // reset them to pending and rebuild the schedule so resume can't hang
                for i in self.chunks.indices where self.chunks[i].status == .downloading {
                    self.chunks[i].status = .pending
                }
                self.pendingIndices = self.chunks.filter { $0.status == .pending }.map(\.index)
                self.dispatchNext()
            }
        }
    }

    public func cancel() {
        EngineLog.manager.notice("cancel")
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.logTimer?.invalidate()
            self.logTimer = nil
            self.bucket.stop()
            for (_, task) in self.activeTasks { task.cancel() }
            self.activeTasks.removeAll()
            self.singleStreamTask?.cancel()
            self.singleStreamTask = nil
            self.pendingIndices.removeAll()
        }
    }

    public var hasActiveTasks: Bool {
        syncQueue.sync { !activeTasks.isEmpty || singleStreamTask != nil }
    }

    // MARK: - Scheduling

    private func updateBucket() {
        bucket.setRate(speedLimit > 0 ? Double(speedLimit) : 0)
    }

    // MARK: - Single-stream mode (used when the server lacks Range support)

    private func enterSingleStream() {
        guard singleStreamTask == nil else { return }
        singleStreamMode = true
        EngineLog.manager.notice("server does not support Range, switch to single-stream from scratch")
        for (_, task) in activeTasks { task.cancel() }
        activeTasks.removeAll()
        pendingIndices.removeAll()
        chunks = []
        totalSize = 0
        lastLogTime = .distantPast
        lastLogBytes = 0
        // cancel() of the old task stops the shared bucket; re-activate it and re-apply the throttle
        bucket.reset(rate: speedLimit > 0 ? Double(speedLimit) : 0)
        onChunksChanged?([])
        lastChunksChangedTime = Date()
        pendingChunksChanged = false

        let task = ChunkDownloadTask(chunkIndex: 0, url: url, fileURL: destinationURL, startOffset: 0, endOffset: Int64.max)
        // Only send a Range header when the probe confirmed the server honors 206.
        // Servers that ignored the probe's Range (200) must get a plain GET, or they
        // may drop the Range or behave inconsistently.
        task.requestsWholeFile = (serverSupportsResume != true)
        task.bucket = bucket
        task.onProgress = { [weak self] (bytes: Int64) in
            guard let self else { return }
            self.syncQueue.async {
                self.singleStreamBytes = bytes
                self.updateSingleStreamProgress()
            }
        }
        task.onTotalSizeKnown = { [weak self] (total: Int64) in
            guard let self else { return }
            self.syncQueue.async {
                guard total > 0 else { return }
                self.singleStreamTotal = total
                self.totalSize = total
            }
        }
        task.onSupportsResume = { [weak self] (_: Bool) in
            guard let self else { return }
            self.syncQueue.async {
                guard self.serverSupportsResume == nil else { return }
                self.serverSupportsResume = false
                self.onResumeSupport?(false)
            }
        }
        task.onCompletion = { [weak self] (result: Result<Void, Error>) in
            guard let self else { return }
            self.syncQueue.async {
                self.singleStreamTask = nil
                self.activeTasks.removeAll()
                self.logTimer?.invalidate()
                self.logTimer = nil
                switch result {
                case .success:
                    self.onProgress?(self.singleStreamTotal, self.singleStreamTotal, self.downloadSpeed)
                    self.onCompletion?(.success(()))
                case .failure(let error):
                    self.lastError = error
                    self.onCompletion?(.failure(error))
                }
            }
        }
        singleStreamTask = task
        task.start(resumeFrom: 0)
    }

    private func updateSingleStreamProgress() {
        let now = Date()
        if lastLogTime == .distantPast {
            lastLogTime = now
            lastLogBytes = singleStreamBytes
        }
        let elapsed = now.timeIntervalSince(lastLogTime)
        if elapsed >= EngineConstants.speedReportInterval {
            downloadSpeed = Int64(Double(singleStreamBytes - lastLogBytes) / elapsed)
            lastLogTime = now
            lastLogBytes = singleStreamBytes
        }
        let total = max(singleStreamTotal, singleStreamBytes)
        onProgress?(singleStreamBytes, total, downloadSpeed)
    }

    private func dispatchNext() {
        let activeCount = activeTasks.count
        let canStart = max(0, maxConcurrent - activeCount)
        if canStart > 0, !pendingIndices.isEmpty {
            var started = 0
            while started < canStart, !pendingIndices.isEmpty {
                let idx = pendingIndices.removeFirst()
                guard idx < chunks.count, chunks[idx].status != .completed else { continue }
                chunks[idx].status = .downloading

                let chunk = chunks[idx]
                let task = ChunkDownloadTask(
                    chunkIndex: idx,
                    url: url,
                    fileURL: destinationURL,
                    startOffset: chunk.startOffset,
                    endOffset: chunk.endOffset
                )
                task.bucket = bucket
                setupTask(task, index: idx)
                activeTasks[idx] = task
                task.start(resumeFrom: chunks[idx].downloadedSize)
                started += 1
            }
        }
        let completed = chunks.filter { $0.status == .completed }.count
        EngineLog.manager.debug("dispatch active=\(self.activeTasks.count)/\(self.maxConcurrent) pending=\(self.pendingIndices.count) done=\(completed)/\(self.chunks.count) speed=\(self.downloadSpeed)/s")
    }

    private func checkDone() {
        let done = chunks.filter { $0.status == .completed }.count
        let failed = chunks.filter { $0.status == .failed }.count
        guard totalSize > 0 || singleStreamMode else { return }
        if done + failed >= chunks.count, !chunks.isEmpty {
            logTimer?.invalidate()
            logTimer = nil
            // Flush the final chunk state before reporting done so the app
            // persists/displayed chunks are never stale from throttling.
            notifyChunksChanged(force: true)
            if failed > 0 {
                for (_, task) in activeTasks { task.cancel() }
                activeTasks.removeAll()
                pendingIndices.removeAll()
                onCompletion?(.failure(lastError ?? DownloadError.cancelled))
            } else {
                onCompletion?(.success(()))
            }
        }
    }

    // MARK: - Progress

    /// Delivers the chunk array to the app at most once per interval. Per-chunk
    /// completions coalesce (a 5863-chunk file would otherwise fire 5863 full
    /// array copies); structural changes use `force` to deliver immediately.
    /// Call on syncQueue.
    private func notifyChunksChanged(force: Bool = false) {
        let now = Date()
        if force || now.timeIntervalSince(lastChunksChangedTime) >= EngineConstants.chunksChangedInterval {
            lastChunksChangedTime = now
            pendingChunksChanged = false
            onChunksChanged?(chunks)
        } else if !pendingChunksChanged {
            pendingChunksChanged = true
            syncQueue.asyncAfter(deadline: .now() + EngineConstants.chunksChangedInterval) { [weak self] in
                guard let self else { return }
                if self.pendingChunksChanged {
                    self.lastChunksChangedTime = Date()
                    self.pendingChunksChanged = false
                    self.onChunksChanged?(self.chunks)
                }
            }
        }
    }

    private func updateProgress() {
        var written: Int64 = 0
        for c in chunks {
            switch c.status {
            case .completed: written += c.size
            case .downloading: written += c.downloadedSize
            default: break
            }
        }
        let now = Date()
        if lastLogTime == .distantPast {
            lastLogTime = now
            lastLogBytes = written
        }
        let elapsed = now.timeIntervalSince(lastLogTime)
        // Average speed over the last full second; recompute at most once a second.
        if elapsed >= EngineConstants.speedReportInterval {
            downloadSpeed = Int64(Double(written - lastLogBytes) / elapsed)
            lastLogTime = now
            lastLogBytes = written
        }
        let total = chunks.last?.endOffset ?? totalSize
        onProgress?(written, total, downloadSpeed)
    }

    private func startLogTimer() {
        logTimer?.invalidate()
        logTimer = Timer.scheduledTimer(withTimeInterval: EngineConstants.statusLogInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.syncQueue.async {
                EngineLog.manager.debug("status active=\(self.activeTasks.count)/\(self.maxConcurrent) pending=\(self.pendingIndices.count) done=\(self.chunks.filter { $0.status == .completed }.count)/\(self.chunks.count) speed=\(self.downloadSpeed)/s")
            }
        }
    }

    // MARK: - Helpers

    public func buildChunks(totalSize: Int64, chunkSize: Int64) -> [Chunk] {
        Chunk.chunks(totalSize: totalSize, chunkSize: chunkSize)
    }
}
