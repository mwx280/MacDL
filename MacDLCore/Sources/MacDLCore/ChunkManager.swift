import Foundation
import os

// Shared byte-level token bucket for smooth throttling across all chunks.
public final class TokenBucket {
    private let lock = NSLock()
    private var rate: Double
    private var tokens: Double = 0
    private var lastRefill = Date()
    private var stopped = false

    public init(rate: Double) {
        self.rate = max(0, rate)
    }

    public func setRate(_ newRate: Double) {
        lock.lock()
        rate = max(0, newRate)
        lock.unlock()
    }

    public func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    public func reset(rate newRate: Double) {
        lock.lock()
        stopped = false
        rate = max(0, newRate)
        tokens = 0
        lastRefill = Date()
        lock.unlock()
    }

    /// Blocks until `amount` bytes can be consumed, or until `stop()` is called. Returns false when stopped.
    @discardableResult
    public func take(_ amount: Double) -> Bool {
        while true {
            lock.lock()
            if stopped {
                lock.unlock()
                return false
            }
            if rate <= 0 {
                lock.unlock()
                return true
            }
            let now = Date()
            let elapsed = now.timeIntervalSince(lastRefill)
            if elapsed > 0 {
                tokens += rate * elapsed
                lastRefill = now
                // Token cap: allows ~2s of burst, but at least 1MB so a single take(<=1MB) always succeeds and low-speed throttling can't deadlock
                tokens = min(tokens, max(rate * 2, 1_048_576))
            }
            if tokens >= amount {
                tokens -= amount
                lock.unlock()
                return true
            }
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
}

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

    private let maxRetries = 3
    private let bucket = TokenBucket(rate: 0)

    private let syncQueue = DispatchQueue(label: "com.xiaowu.chunkmanager.sync")
    private var logTimer: Timer?
    private var lastLogBytes: Int64 = 0
    private var lastLogTime: Date = .distantPast

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
        os_log("[ChunkManager] start probe chunkSize=%lld maxConcurrent=%d", chunkSize, maxConcurrent)
        startLogTimer()
        syncQueue.async { self.startProbe() }
    }

    public func start(withChunks existing: [Chunk], totalSize: Int64) {
        os_log("[ChunkManager] resume chunks=%d pending=%d completed=%d total=%lld",
               existing.count,
               existing.filter { $0.status != .completed }.count,
               existing.filter { $0.status == .completed }.count, totalSize)
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
                os_log("[ChunkManager] totalSize=%lld", total)
                guard !self.singleStreamMode else { return }
                let built = self.buildChunks(totalSize: total, chunkSize: self.chunkSize)
                self.chunks = built
                self.chunks[0].status = .downloading
                self.chunks[0].downloadedSize = 0
                self.pendingIndices = Array(1..<built.count)
                self.onChunksChanged?(self.chunks)
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
                os_log("[ChunkManager] server total=%lld differs from %lld, abort resume", total, self.totalSize)
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
                    os_log("[ChunkManager] chunk %d completed", index)
                    if self.totalSize == 0, self.chunks.count == 1, !self.singleStreamMode {
                        os_log("[ChunkManager] probe completed without file size, falling back to single-stream")
                        self.enterSingleStream()
                        return
                    }
                case .failure(let error):
                    self.handleChunkFailure(index, error: error)
                }
                self.updateProgress()
                self.onChunksChanged?(self.chunks)
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
            os_log("[ChunkManager] chunk %d failed permanently (%{public}@)", index, dlError.errorDescription ?? "?")
            return
        }
        let attempt = (retryCounts[index] ?? 0) + 1
        guard attempt <= maxRetries else {
            lastError = error
            chunks[index].status = .failed
            os_log("[ChunkManager] chunk %d failed permanently after %d attempts", index, maxRetries)
            return
        }
        retryCounts[index] = attempt
        chunks[index].status = .pending
        pendingIndices.append(index)
        pendingIndices.sort()
        // Exponential backoff: 1s, 2s, 4s... capped at 10s.
        let delay = min(1.0 * pow(2.0, Double(attempt - 1)), 10.0)
        os_log("[ChunkManager] chunk %d failed, retry %d/%d in %.1fs", index, attempt, maxRetries, delay)
        syncQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.dispatchNext()
        }
    }

    public func setSpeedLimit(_ limit: Int64) {
        os_log("[ChunkManager] speedLimit=%lld/s", limit)
        syncQueue.async {
            self.speedLimit = limit
            self.updateBucket()
        }
    }

    public func setMaxConcurrent(_ max: Int) {
        maxConcurrent = max
        os_log("[ChunkManager] maxConcurrent=%d", max)
        syncQueue.async { self.dispatchNext() }
    }

    public func pause() {
        os_log("[ChunkManager] pause")
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
        os_log("[ChunkManager] resume")
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
        os_log("[ChunkManager] cancel")
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
        os_log("[ChunkManager] server does not support Range, switch to single-stream from scratch")
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

        let task = ChunkDownloadTask(chunkIndex: 0, url: url, fileURL: destinationURL, startOffset: 0, endOffset: Int64.max)
        task.requestsWholeFile = false
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
        if elapsed >= 1.0 {
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
        os_log("[ChunkManager] dispatch active=%d/%d pending=%d done=%d/%d speed=%lld/s",
               activeTasks.count, maxConcurrent, pendingIndices.count,
               chunks.filter { $0.status == .completed }.count, chunks.count, downloadSpeed)
    }

    private func checkDone() {
        let done = chunks.filter { $0.status == .completed }.count
        let failed = chunks.filter { $0.status == .failed }.count
        guard totalSize > 0 || singleStreamMode else { return }
        if done + failed >= chunks.count, !chunks.isEmpty {
            logTimer?.invalidate()
            logTimer = nil
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
        if elapsed >= 1.0 {
            downloadSpeed = Int64(Double(written - lastLogBytes) / elapsed)
            lastLogTime = now
            lastLogBytes = written
        }
        let total = chunks.last?.endOffset ?? totalSize
        onProgress?(written, total, downloadSpeed)
    }

    private func startLogTimer() {
        logTimer?.invalidate()
        logTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.syncQueue.async {
                os_log("[ChunkManager] status active=%d/%d pending=%d done=%d/%d speed=%lld/s",
                       self.activeTasks.count, self.maxConcurrent, self.pendingIndices.count,
                       self.chunks.filter { $0.status == .completed }.count, self.chunks.count, self.downloadSpeed)
            }
        }
    }

    // MARK: - Helpers

    public func buildChunks(totalSize: Int64, chunkSize: Int64) -> [Chunk] {
        let cs = max(Int64(1), chunkSize)
        var result: [Chunk] = []
        var offset: Int64 = 0
        var index = 0
        while offset < totalSize {
            let end = min(offset + cs, totalSize)
            result.append(Chunk(index: index, startOffset: offset, endOffset: end, downloadedSize: 0, status: .pending))
            offset = end
            index += 1
        }
        return result
    }
}
