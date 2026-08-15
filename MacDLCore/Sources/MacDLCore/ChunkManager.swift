import Foundation

// All mutable state lives on syncQueue. Every callback re-enters through
// syncQueue.async, so nothing is ever touched from two threads at once.
/// Schedules and tracks the chunks of one download: runs the Range probe,
/// splits the file, dispatches chunk tasks up to the connection cap, retries
/// failures with backoff, and falls back to a single stream when the server
/// does not honour Range requests.
/// @unchecked Sendable: all mutable state lives on `syncQueue` and every
/// callback re-enters through it, so no state is touched from two threads.
public final class ChunkManager: @unchecked Sendable {
    /// Unique download identifier, also used as the engine registration key.
    public let id: UUID
    /// Remote source URL.
    public let url: URL
    /// Local file every chunk writes into.
    public let destinationURL: URL
    /// Byte range each chunk covers.
    public private(set) var chunkSize: Int64
    /// Total file size, known once the probe (or resume) reports it.
    public private(set) var totalSize: Int64 = 0
    /// Recent throughput in bytes/second, recomputed once per second.
    public private(set) var downloadSpeed: Int64 = 0

    private var maxConcurrent: Int
    private var isAutoConnections = false
    private var autoPolicy = AutoConnectionPolicy()
    private var adaptWorkItem: DispatchWorkItem?
    private var probeStartTime: Date?
    private var probeDataStartTime: Date?
    private var measuredRTT: TimeInterval = 0
    private var rttMeasured = false
    private var historyRTT: TimeInterval?
    private var historyBandwidth: Int64?
    private var downloadStartTime: Date?
    private var speedLimit: Int64 = 0
    private var chunks: [Chunk] = []
    private var sources: [Source] = []
    private var chunkSource: [Int: Int] = [:]
    private var chunkDispatchTime: [Int: Date] = [:]
    private var maxObservedChunkSpeed: Int64 = 0
    private var sourceScheduler: SourceScheduler
    private var completedCount = 0
    private var failedCount = 0
    private var writtenBytes: Int64 = 0
    private var activeTasks: [Int: ChunkDownloadTask] = [:]
    private var pendingIndices: [Int] = []
    private var pendingHead = 0
    private var dirtyIndices = Set<Int>()
    private var retryCounts: [Int: Int] = [:]
    private var lastError: Error?
    private var serverSupportsResume: Bool?
    private var singleStreamMode = false
    private var singleStreamTask: ChunkDownloadTask?
    private var singleStreamTotal: Int64 = 0
    private var singleStreamBytes: Int64 = 0
    private var singleStreamRetries = 0
    private var singleStreamRetryItem: DispatchWorkItem?

    private let maxRetries = EngineConstants.maxChunkRetries
    private let bucket = TokenBucket(rate: 0)

    private let syncQueue = DispatchQueue(label: "com.xiaowu.chunkmanager.sync")
    private var logTimer: Timer?
    private var lastLogBytes: Int64 = 0
    private var lastLogTime: Date = .distantPast
    private var lastChunksChangedTime: Date = .distantPast
    private var pendingChunksChanged = false
    private var isPaused = false
    private var retryWorkItems: [Int: DispatchWorkItem] = [:]

    /// Progress callback: `(writtenBytes, totalBytes, bytesPerSecond)`.
    public var onProgress: ((Int64, Int64, Int64) -> Void)?
    /// Chunk-array callback, delivered at a throttled cadence.
    public var onChunksChanged: (([Chunk]) -> Void)?
    /// Incremental chunk callback: only the chunks that changed since the last
    /// delivery, avoiding a full-array copy on every progress tick.
    public var onChunksUpdated: (([Chunk]) -> Void)?
    /// Completion callback with the overall `Result<Void, Error>`.
    public var onCompletion: ((Result<Void, Error>) -> Void)?
    /// Server resume-support callback.
    public var onResumeSupport: ((Bool) -> Void)?
    /// `true` = range-probe/detection phase (no chunks scheduled yet);
    /// `false` = actual downloading. Set before the probe and when chunks are
    /// built or single-stream begins.
    public var onPhaseChanged: ((Bool) -> Void)?
    /// Called once the probe picked a dynamic chunk size, so the app can persist
    /// it for resume.
    public var onChunkSizeChanged: ((Int64) -> Void)?

    /// Creates a manager for one download. `maxConcurrent <= 0` selects auto
    /// mode: the engine picks the connection count from the probed file size
    /// and adapts it to observed throughput.
    public init(id: UUID, url: URL, destinationURL: URL, chunkSize: Int64, maxConcurrent: Int, mirrors: [URL] = []) {
        self.id = id
        self.url = url
        self.destinationURL = destinationURL
        self.chunkSize = chunkSize
        self.isAutoConnections = maxConcurrent <= 0
        self.maxConcurrent = self.isAutoConnections ? 1 : maxConcurrent
        self.sources = [Source(url: url)] + mirrors.map { Source(url: $0) }
        self.sourceScheduler = SourceScheduler(sourceCount: self.sources.count)
        // Seed cold-start decisions from past sessions for this host, so a
        // repeated source starts near its optimal settings instead of probing
        // from a size-only guess.
        if let h = SourceHistoryStore.shared.history(for: url.host ?? ""), h.sampleCount > 0 {
            self.historyRTT = h.avgRTT
            self.historyBandwidth = h.avgBandwidth
        }
    }

    // MARK: - Public control

    /// Runs the Range probe, then splits the file into chunks and schedules them.
    public func start() {
        EngineLog.manager.notice("start probe chunkSize=\(chunkSize) maxConcurrent=\(maxConcurrent)")
        startLogTimer()
        syncQueue.async {
            self.singleStreamRetries = 0
            self.downloadStartTime = Date()
            self.onPhaseChanged?(true)
            self.startProbe()
        }
    }

    /// Resumes from a persisted chunk list; completed chunks are never re-fetched.
    public func start(withChunks existing: [Chunk], totalSize: Int64) {
        EngineLog.manager.notice("resume chunks=\(existing.count) pending=\(existing.filter { $0.status != .completed }.count) completed=\(existing.filter { $0.status == .completed }.count) total=\(totalSize)")
        startLogTimer()
        syncQueue.async {
            self.singleStreamRetries = 0
            self.downloadStartTime = Date()
            self.onPhaseChanged?(false)
            self.totalSize = totalSize
            self.chunks = existing
            var completed = 0
            var written: Int64 = 0
            for i in self.chunks.indices {
                if self.chunks[i].status == .completed {
                    completed += 1
                    written += self.chunks[i].size
                } else {
                    self.chunks[i].status = .pending
                    written += self.chunks[i].downloadedSize
                }
            }
            self.completedCount = completed
            self.failedCount = 0
            self.writtenBytes = written
            self.pendingIndices = self.chunks.filter { $0.status == .pending }.map(\.index)
            self.pendingHead = 0
            if self.isAutoConnections {
                self.maxConcurrent = max(1, min(
                    AutoConnectionPolicy.initialConnectionCount(fileSize: totalSize, supportsResume: true),
                    EngineConstants.maxAutoConnections))
                self.startAdaptTimer()
                EngineLog.manager.notice("auto resume initial connections=\(self.maxConcurrent)")
            }
            self.updateBucket()
            self.dispatchNext()
            // A resumed download whose persisted chunks are already complete
            // must still fire completion, or a crash between the last chunk
            // write and the rename would leave the task stuck at 100%.
            self.checkDone()
        }
    }

    private func startProbe() {
        updateBucket()
        // The first request is a probe: one chunk with a Range header. It reveals the
        // total size (via Content-Range) and whether the server honors 206 at all;
        // the rest of the file gets chunked only after that.
        let probe = Chunk(index: 0, startOffset: 0, endOffset: chunkSize, downloadedSize: 0, status: .downloading)
        chunks = [probe]
        completedCount = 0
        failedCount = 0
        writtenBytes = 0
        let task = ChunkDownloadTask(chunkIndex: 0, url: url, fileURL: destinationURL, startOffset: 0, endOffset: chunkSize)
        task.bucket = bucket
        chunkSource[0] = 0
        setupTask(task, index: 0)
        task.onTotalSizeKnown = { [weak self] total in
            guard let self else { return }
            self.syncQueue.async {
                self.handleProbeTotalSize(total)
            }
        }
        activeTasks[0] = task
        probeStartTime = Date()
        probeDataStartTime = nil
        task.start(resumeFrom: 0)
    }

    /// Handles the probe's total-size discovery: measures RTT, picks a dynamic
    /// chunk size, splits the file and starts dispatching. Called on syncQueue.
    /// Shared by the initial probe and any failover re-probe (which goes through
    /// `setupTask` rather than the startProbe closure).
    private func handleProbeTotalSize(_ total: Int64) {
        guard total > 0 else { return }
        totalSize = total
        if let start = probeStartTime {
            measuredRTT = Date().timeIntervalSince(start)
            rttMeasured = true
            // Rate sampling starts at the response, excluding connection setup
            // so the single-connection estimate isn't dragged down by high RTT.
            probeDataStartTime = Date()
        }
        EngineLog.manager.notice("totalSize=\(total) rtt=\(measuredRTT)")
        guard !singleStreamMode else { return }
        // Pick a chunk size suited to this file's size and latency before
        // splitting, so large files are not chopped into hundreds of thousands
        // of tiny chunks.
        let dynamicChunkSize = ChunkingPolicy.chunkSize(
            totalSize: total, rtt: historyRTT ?? measuredRTT,
            singleConnRate: historyBandwidth ?? 0)
        if dynamicChunkSize != chunkSize {
            chunkSize = dynamicChunkSize
            onChunkSizeChanged?(dynamicChunkSize)
        }
        let built = buildChunks(totalSize: total, chunkSize: chunkSize)
        chunks = built
        completedCount = 0
        failedCount = 0
        writtenBytes = 0
        chunks[0].status = .downloading
        chunks[0].downloadedSize = 0
        pendingIndices = Array(1..<built.count)
        pendingHead = 0
        if isAutoConnections {
            if let bw = historyBandwidth {
                maxConcurrent = max(1, min(
                    AutoConnectionPolicy.informedInitialConnectionCount(
                        singleConnRate: bw, fileSize: total, rtt: historyRTT ?? measuredRTT),
                    EngineConstants.maxAutoConnections))
                EngineLog.manager.notice("auto historical connections=\(maxConcurrent) bw=\(bw)")
            } else {
                maxConcurrent = max(1, min(
                    AutoConnectionPolicy.initialConnectionCount(fileSize: total, supportsResume: true, rtt: measuredRTT),
                    EngineConstants.maxAutoConnections))
                EngineLog.manager.notice("auto initial connections=\(maxConcurrent)")
            }
            startAdaptTimer()
        }
        notifyChunksChanged(force: true)
        onPhaseChanged?(false)
        dispatchNext()
    }

    private func setupTask(_ task: ChunkDownloadTask, index: Int) {
        task.onProgress = { [weak self] bytes in
            guard let self else { return }
            self.syncQueue.async {
                guard index < self.chunks.count else { return }
                self.writtenBytes += bytes - self.chunks[index].downloadedSize
                self.chunks[index].downloadedSize = bytes
                self.markChunkDirty(index)
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
                guard total > 0 else { return }
                // A failover re-probe runs the probe chunk through setupTask, so
                // split the file here the same way the initial probe does.
                if self.totalSize == 0 {
                    self.handleProbeTotalSize(total)
                    return
                }
                // Resume: the server file size doesn't match the persisted total,
                // so safe resume isn't possible.
                guard total != self.totalSize else { return }
                EngineLog.manager.error("server total=\(total) differs from \(self.totalSize), abort resume")
                self.lastError = DownloadError.fileChanged
                for (_, t) in self.activeTasks { t.cancel() }
                self.activeTasks.removeAll()
                self.clearPending()
                self.logTimer?.invalidate()
                self.logTimer = nil
                self.onCompletion?(.failure(DownloadError.fileChanged))
            }
        }
        task.onCompletion = { [weak self] result in
            guard let self else { return }
            self.syncQueue.async {
                self.activeTasks.removeValue(forKey: index)
                var willRetry = false
                switch result {
                case .success:
                    guard index < self.chunks.count else { return }
                    // Guard against short reads: a chunk that finished with fewer
                    // bytes than its range (server closed early / bucket stopped)
                    // must never be marked complete.
                    if self.chunks[index].downloadedSize < self.chunks[index].size {
                        EngineLog.manager.warning("chunk \(index) short read \(self.chunks[index].downloadedSize)/\(self.chunks[index].size), retrying")
                        willRetry = self.handleChunkFailure(index, error: DownloadError.network(URLError(.resourceUnavailable)))
                    } else {
                        self.writtenBytes += self.chunks[index].size - self.chunks[index].downloadedSize
                        self.chunks[index].status = .completed
                        self.chunks[index].downloadedSize = self.chunks[index].size
                        self.completedCount += 1
                        self.markChunkDirty(index)
                        self.retryCounts[index] = nil
                        // A successful chunk clears its source's failure streak
                        // and folds its throughput into the source's EWMA weight.
                        if let si = self.chunkSource.removeValue(forKey: index) {
                            self.sources[si].recordSuccess()
                            if let start = self.chunkDispatchTime.removeValue(forKey: index) {
                                let elapsed = Date().timeIntervalSince(start)
                                if elapsed > 0.05 {
                                    let rate = Int64(Double(self.chunks[index].size) / elapsed)
                                    self.sources[si].recordThroughput(rate)
                                    self.maxObservedChunkSpeed = max(self.maxObservedChunkSpeed, rate)
                                    // Soft rate-limiting: a chunk far slower than the
                                    // fastest seen one (while others run fast) means the
                                    // server throttles extra concurrent requests, not
                                    // that the network is slow. Degrade the count.
                                    if rate < 1_000_000, self.maxObservedChunkSpeed > 5_000_000 {
                                        self.handleSlowChunk()
                                    }
                                }
                            }
                        }
                        EngineLog.manager.notice("chunk \(index) completed")
                        // The probe chunk doubles as a single-connection speed
                        // sample: refine the initial count from its measured
                        // throughput instead of climbing one step at a time.
                        if self.isAutoConnections, index == 0, self.rttMeasured {
                            let rateStart = self.probeDataStartTime ?? self.probeStartTime
                            if let rateStart {
                                let elapsed = Date().timeIntervalSince(rateStart)
                                let rate = elapsed > 0.01 ? Int64(Double(self.chunks[index].downloadedSize) / elapsed) : 0
                                let prev = self.maxConcurrent
                                self.maxConcurrent = Swift.max(1, Swift.min(
                                    AutoConnectionPolicy.informedInitialConnectionCount(
                                        singleConnRate: rate, fileSize: self.totalSize, rtt: self.measuredRTT),
                                    EngineConstants.maxAutoConnections))
                                // Treat an upward informed jump as a probe so the
                                // next evaluation confirms it against the gain
                                // threshold instead of trusting the estimate.
                                if self.maxConcurrent > prev {
                                    self.autoPolicy.noteInformedProbe(from: prev)
                                }
                                EngineLog.manager.notice("auto informed connections=\(self.maxConcurrent) probeRate=\(rate)")
                            }
                        }
                        if self.totalSize == 0, self.chunks.count == 1, !self.singleStreamMode {
                            EngineLog.manager.notice("probe completed without file size, falling back to single-stream")
                            self.enterSingleStream()
                            return
                        }
                    }
                case .failure(let error):
                    willRetry = self.handleChunkFailure(index, error: error)
                }
                self.updateProgress()
                self.notifyChunksChanged()
                self.checkDone()
                // When a retry is scheduled, leave the slot open until the backoff
                // timer fires — filling it immediately plus the retry would double
                // connection churn during a 429/5xx storm.
                if !willRetry {
                    self.dispatchNext()
                }
            }
        }
    }

    /// Returns true when a retry was scheduled (the caller should NOT immediately
    /// re-dispatch, so a 429/5xx storm doesn't double-open connections).
    @discardableResult
    private func handleChunkFailure(_ index: Int, error: Error) -> Bool {
        guard index < chunks.count else { return false }
        // A 429 means the server rate-limits concurrent requests. Degrade to a
        // single connection immediately instead of letting the adaptive policy
        // thrash between retries and more 429s.
        if (error as? DownloadError) == .httpStatus(429) {
            handleRateLimit()
        }
        // Feed retryable failures (429/5xx/network) to the auto policy so a
        // stressed server stops being probed upward.
        if isAutoConnections, (error as? DownloadError)?.isRetryable != false {
            autoPolicy.recordFailure()
        }
        if let dlError = error as? DownloadError, !dlError.isRetryable {
            lastError = error
            writtenBytes -= chunks[index].downloadedSize
            chunks[index].status = .failed
            failedCount += 1
            markChunkDirty(index)
            EngineLog.manager.error("chunk \(index) failed permanently (\(dlError.errorDescription ?? "?"))")
            return false
        }
        // Failover: when the chunk's source goes into cooldown and another source
        // is available, requeue the chunk so the next dispatch picks the healthy
        // source instead of the failing one. Returns false (no backoff timer) so
        // the caller re-dispatches now. Without an alternative source the chunk
        // keeps the normal retry path (and fails once retries are exhausted).
        if sources.count > 1, let si = chunkSource[index] {
            sources[si].recordFailure(now: Date(),
                                      threshold: EngineConstants.sourceFailureThreshold,
                                      cooldown: EngineConstants.sourceCooldownInterval)
            if !sources[si].isAvailable() {
                let hasAlternative = sources.enumerated().contains { $0.offset != si && $0.element.isAvailable() }
                if hasAlternative {
                    EngineLog.manager.warning("source \(si) cooled down, failing chunk \(index) over")
                    chunkSource[index] = nil
                    retryCounts[index] = 0
                    writtenBytes -= chunks[index].downloadedSize
                    chunks[index].status = .pending
                    markChunkDirty(index)
                    enqueuePending(index)
                    return false
                }
            }
        }
        let attempt = (retryCounts[index] ?? 0) + 1
        guard attempt <= maxRetries else {
            lastError = error
            writtenBytes -= chunks[index].downloadedSize
            chunks[index].status = .failed
            failedCount += 1
            markChunkDirty(index)
            EngineLog.manager.error("chunk \(index) failed permanently after \(self.maxRetries) attempts")
            return false
        }
        retryCounts[index] = attempt
        writtenBytes -= chunks[index].downloadedSize
        chunks[index].status = .pending
        markChunkDirty(index)
        enqueuePending(index)
        // Exponential backoff: 1s, 2s, 4s... capped at 10s.
        let delay = min(EngineConstants.retryBackoffBase * pow(2.0, Double(attempt - 1)), EngineConstants.retryBackoffCap)
        EngineLog.manager.warning("chunk \(index) failed, retry \(attempt)/\(self.maxRetries) in \(delay)s")
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.retryWorkItems.removeValue(forKey: index)
            guard !self.isPaused else { return }
            self.dispatchNext()
        }
        retryWorkItems[index]?.cancel()
        retryWorkItems[index] = item
        syncQueue.asyncAfter(deadline: .now() + delay, execute: item)
        return true
    }

    /// Degrades to a single connection when the server signals hard rate-limiting
    /// (HTTP 429), and stops the adaptive timer so it stays there for this
    /// session. The adaptive policy's "try more connections" assumption is wrong
    /// for such servers — the second concurrent request is rejected outright.
    private func handleRateLimit() {
        degradeConcurrency(to: 1)
    }

    /// Soft rate-limiting (a chunk throttled far below the fastest one while
    /// others run fast): halve the connection count, converging toward the level
    /// the server actually tolerates instead of a hard drop to one.
    private func handleSlowChunk() {
        degradeConcurrency(to: max(1, maxConcurrent / 2))
    }

    /// Lowers the connection cap, locks the adaptive policy at that ceiling and
    /// stops the adaptive timer so it does not probe back up into the limit.
    private func degradeConcurrency(to count: Int) {
        guard isAutoConnections, maxConcurrent > count else { return }
        EngineLog.manager.warning("degrading connections \(maxConcurrent) -> \(count)")
        maxConcurrent = count
        stopAdaptTimer()
        autoPolicy.forceConcurrencyCeiling(count)
    }

    /// Updates the byte/second throttle shared by all chunks of this download.
    public func setSpeedLimit(_ limit: Int64) {
        EngineLog.manager.notice("speedLimit=\(limit)/s")
        syncQueue.async {
            self.speedLimit = limit
            self.updateBucket()
        }
    }

    /// Updates the parallel-connection cap and re-dispatches pending chunks.
    /// A non-positive value switches the download into auto mode (adaptive
    /// connection tuning); a positive value switches back to a fixed cap.
    public func setMaxConcurrent(_ maxConcurrent: Int) {
        EngineLog.manager.notice("setMaxConcurrent=\(maxConcurrent)")
        syncQueue.async {
            if maxConcurrent <= 0 {
                if !self.isAutoConnections {
                    self.isAutoConnections = true
                    self.autoPolicy.reset()
                    self.maxConcurrent = Swift.max(1, Swift.min(
                        AutoConnectionPolicy.initialConnectionCount(fileSize: self.totalSize, supportsResume: true),
                        EngineConstants.maxAutoConnections))
                    self.startAdaptTimer()
                    EngineLog.manager.notice("auto connections enabled, initial=\(self.maxConcurrent)")
                }
            } else {
                if self.isAutoConnections {
                    self.isAutoConnections = false
                    self.stopAdaptTimer()
                }
                self.maxConcurrent = Swift.max(1, maxConcurrent)
            }
            self.dispatchNext()
        }
    }

    /// Pauses the download: freezes scheduling, cancels retry timers and stops
    /// the throttle so nothing can resume until `resume()`.
    public func pause() {
        EngineLog.manager.notice("pause")
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.isPaused = true
            self.logTimer?.invalidate()
            self.logTimer = nil
            self.stopAdaptTimer()
            self.bucket.stop()
            // Freeze scheduling: cancel pending retries and clear the queue so
            // nothing can start new chunk tasks while paused.
            for (_, item) in self.retryWorkItems { item.cancel() }
            self.retryWorkItems.removeAll()
            self.singleStreamRetryItem?.cancel()
            self.singleStreamRetryItem = nil
            self.clearPending()
            for (_, task) in self.activeTasks { task.pause() }
            self.activeTasks.removeAll()
            self.singleStreamTask?.pause()
            self.singleStreamTask = nil
        }
    }

    /// Resumes a paused download, rebuilding the schedule from chunk state.
    public func resume() {
        EngineLog.manager.notice("resume")
        startLogTimer()
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.isPaused = false
            self.singleStreamRetries = 0
            self.singleStreamRetryItem?.cancel()
            self.singleStreamRetryItem = nil
            if self.isAutoConnections { self.startAdaptTimer() }
            self.bucket.reset(rate: self.speedLimit > 0 ? Double(self.speedLimit) : 0)
            if self.singleStreamMode {
                self.enterSingleStream()
            } else {
                // pause() clears activeTasks, orphaning in-flight (.downloading) chunks;
                // reset them to pending and rebuild the schedule so resume can't hang
                for i in self.chunks.indices where self.chunks[i].status == .downloading {
                    self.writtenBytes -= self.chunks[i].downloadedSize
                    self.chunks[i].status = .pending
                    self.markChunkDirty(i)
                }
                self.pendingIndices = self.chunks.filter { $0.status == .pending }.map(\.index)
                self.pendingHead = 0
                self.dispatchNext()
                self.checkDone()
            }
        }
    }

    /// Cancels every in-flight task and clears all scheduling state.
    public func cancel() {
        EngineLog.manager.notice("cancel")
        syncQueue.async { [weak self] in
            guard let self else { return }
            self.isPaused = false
            self.logTimer?.invalidate()
            self.logTimer = nil
            self.stopAdaptTimer()
            self.bucket.stop()
            for (_, item) in self.retryWorkItems { item.cancel() }
            self.retryWorkItems.removeAll()
            self.singleStreamRetryItem?.cancel()
            self.singleStreamRetryItem = nil
            for (_, task) in self.activeTasks { task.cancel() }
            self.activeTasks.removeAll()
            self.singleStreamTask?.cancel()
            self.singleStreamTask = nil
            self.clearPending()
        }
    }

    /// True while any chunk task or the single-stream task is transferring.
    public var hasActiveTasks: Bool {
        syncQueue.sync { !activeTasks.isEmpty || singleStreamTask != nil }
    }
    // MARK: - Scheduling

    /// Number of chunks still waiting to be dispatched (not yet consumed by the
    /// `pendingHead` cursor).
    private var pendingCount: Int { pendingIndices.count - pendingHead }

    /// Appends a chunk index to the pending queue. The array is consumed by a
    /// cursor instead of `removeFirst()`, so appends are O(1) amortized; the
    /// array is compacted once every element before the cursor has been spent.
    private func enqueuePending(_ index: Int) {
        if pendingHead > 0, pendingHead == pendingIndices.count {
            pendingIndices.removeAll(keepingCapacity: true)
            pendingHead = 0
        }
        pendingIndices.append(index)
    }

    /// Empties the pending queue and resets the cursor.
    private func clearPending() {
        pendingIndices.removeAll(keepingCapacity: true)
        pendingHead = 0
    }

    private func updateBucket() {
        bucket.setRate(speedLimit > 0 ? Double(speedLimit) : 0)
    }

    // MARK: - Single-stream mode (used when the server lacks Range support)

    private func enterSingleStream() {
        guard singleStreamTask == nil else { return }
        singleStreamMode = true
        stopAdaptTimer()
        onPhaseChanged?(false)
        EngineLog.manager.notice("server does not support Range, switch to single-stream from scratch")
        for (_, task) in activeTasks { task.cancel() }
        activeTasks.removeAll()
        clearPending()
        chunks = []
        dirtyIndices.removeAll()
        completedCount = 0
        failedCount = 0
        writtenBytes = 0
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
                    // Backfill the real size now that the stream finished, so the
                    // final progress report and persisted state carry the actual total.
                    self.singleStreamTotal = self.singleStreamBytes
                    self.onProgress?(self.singleStreamTotal, self.singleStreamTotal, self.downloadSpeed)
                    self.onCompletion?(.success(()))
                case .failure(let error):
                    // Give a slow/flaky server one quick retry before failing.
                    // Never retry a user cancel, and skip when paused.
                    let isCancelled = (error as? DownloadError) == .cancelled
                    if !isCancelled, !self.isPaused, self.singleStreamRetries < EngineConstants.maxSingleStreamRetries {
                        self.singleStreamRetries += 1
                        EngineLog.manager.warning("single-stream failed (\(error.localizedDescription)), retry \(self.singleStreamRetries)/\(EngineConstants.maxSingleStreamRetries)")
                        self.bucket.reset(rate: self.speedLimit > 0 ? Double(self.speedLimit) : 0)
                        // Keep the retry cancellable so pause()/cancel() can stop it —
                        // otherwise a stale retry would restart the download after the
                        // user asked to stop.
                        let item = DispatchWorkItem { [weak self] in self?.enterSingleStream() }
                        self.singleStreamRetryItem = item
                        self.syncQueue.asyncAfter(deadline: .now() + EngineConstants.singleStreamRetryDelay, execute: item)
                    } else {
                        self.lastError = error
                        self.onCompletion?(.failure(error))
                    }
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
            if isAutoConnections { autoPolicy.record(speed: downloadSpeed) }
        }
        let total = singleStreamTotal > 0 ? singleStreamTotal : 0
        onProgress?(singleStreamBytes, total, downloadSpeed)
    }

    private func dispatchNext() {
        guard !isPaused else { return }
        let activeCount = activeTasks.count
        let canStart = max(0, maxConcurrent - activeCount)
        if canStart > 0, pendingHead < pendingIndices.count {
            var started = 0
            while started < canStart, pendingHead < pendingIndices.count {
                let idx = pendingIndices[pendingHead]
                pendingHead += 1
                guard idx < chunks.count, chunks[idx].status != .completed else { continue }
                // Weighted round-robin across healthy sources: faster sources
                // (higher EWMA throughput) serve more chunks, and cooling-down
                // sources get none.
                let throughputs = sources.map(\.avgThroughput)
                let available = sources.map { $0.isAvailable() }
                guard let si = sourceScheduler.pick(throughputs: throughputs, available: available) else {
                    // No source is usable right now: stop dispatching and let
                    // the cooldown timer re-enter dispatch when one recovers.
                    scheduleSourceRecovery()
                    break
                }
                chunkSource[idx] = si
                chunkDispatchTime[idx] = Date()
                writtenBytes += chunks[idx].downloadedSize
                chunks[idx].status = .downloading
                markChunkDirty(idx)

                let chunk = chunks[idx]
                let task = ChunkDownloadTask(
                    chunkIndex: idx,
                    url: sources[si].url,
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
        let completed = completedCount
        EngineLog.manager.debug("dispatch active=\(self.activeTasks.count)/\(self.maxConcurrent) pending=\(self.pendingCount) done=\(completed)/\(self.chunks.count) speed=\(self.downloadSpeed)/s")
    }

    /// Schedules a re-dispatch when the earliest cooldown expires, so chunks do
    /// not sit pending forever while every source is cooling down.
    private func scheduleSourceRecovery() {
        let earliest = sources.compactMap(\.cooldownUntil).min()
        guard let earliest else { return }
        let delay = max(0.1, earliest.timeIntervalSinceNow)
        syncQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            guard !self.isPaused else { return }
            self.dispatchNext()
        }
    }

    private func checkDone() {
        let done = completedCount
        let failed = failedCount
        guard done + failed >= chunks.count, !chunks.isEmpty else { return }
        logTimer?.invalidate()
        logTimer = nil
        stopAdaptTimer()
        // Flush the final chunk state before reporting done so the app
        // persists/displayed chunks are never stale from throttling.
        notifyChunksChanged(force: true)
        if failed > 0 {
            // A failed download reports its error even when the total size is
            // still unknown (e.g. the Range probe exhausted its retries on a
            // pure network failure) — otherwise the task would hang forever.
            for (_, task) in activeTasks { task.cancel() }
            activeTasks.removeAll()
            clearPending()
            recordHistory(success: false)
            onCompletion?(.failure(lastError ?? DownloadError.cancelled))
        } else if totalSize > 0 || singleStreamMode {
            recordHistory(success: true)
            onCompletion?(.success(()))
        }
    }

    /// Folds this download's measured bandwidth and latency into the per-host
    /// history so a repeated source starts near its learned optimum.
    private func recordHistory(success: Bool) {
        guard totalSize > 0, let start = downloadStartTime else { return }
        let host = url.host ?? ""
        guard !host.isEmpty else { return }
        let elapsed = Date().timeIntervalSince(start)
        let bandwidth = elapsed > 0.1 ? Int64(Double(totalSize) / elapsed) : 0
        guard bandwidth > 0 else { return }
        SourceHistoryStore.shared.record(host: host, bandwidth: bandwidth,
                                         rtt: measuredRTT, success: success,
                                         supportsRange: serverSupportsResume)
    }

    // MARK: - Progress

    /// Marks a chunk as changed so the next flush delivers only that chunk
    /// instead of the whole array (avoids full-array copy-on-write churn).
    private func markChunkDirty(_ index: Int) {
        dirtyIndices.insert(index)
    }

    /// Sends the chunks that changed since the last delivery. Call on syncQueue.
    private func flushDirtyChunks() {
        guard !dirtyIndices.isEmpty else { return }
        let updates = dirtyIndices.compactMap { idx -> Chunk? in
            idx < chunks.count ? chunks[idx] : nil
        }
        dirtyIndices.removeAll()
        onChunksUpdated?(updates)
    }

    /// Delivers chunk state to the app at most once per interval. Structural
    /// changes use `force` to deliver the full array; incremental changes flush
    /// only the dirty chunks so large files avoid a full-array copy per tick.
    /// Call on syncQueue.
    private func notifyChunksChanged(force: Bool = false) {
        if force {
            lastChunksChangedTime = Date()
            pendingChunksChanged = false
            dirtyIndices.removeAll()
            onChunksChanged?(chunks)
            return
        }
        let now = Date()
        if now.timeIntervalSince(lastChunksChangedTime) >= EngineConstants.chunksChangedInterval {
            lastChunksChangedTime = now
            pendingChunksChanged = false
            flushDirtyChunks()
        } else if !pendingChunksChanged {
            pendingChunksChanged = true
            syncQueue.asyncAfter(deadline: .now() + EngineConstants.chunksChangedInterval) { [weak self] in
                guard let self else { return }
                if self.pendingChunksChanged {
                    self.lastChunksChangedTime = Date()
                    self.pendingChunksChanged = false
                    self.flushDirtyChunks()
                }
            }
        }
    }

    private func updateProgress() {
        let now = Date()
        if lastLogTime == .distantPast {
            lastLogTime = now
            lastLogBytes = writtenBytes
        }
        let elapsed = now.timeIntervalSince(lastLogTime)
        // Average speed over the last full second; recompute at most once a second.
        if elapsed >= EngineConstants.speedReportInterval {
            downloadSpeed = Int64(Double(writtenBytes - lastLogBytes) / elapsed)
            lastLogTime = now
            lastLogBytes = writtenBytes
            if isAutoConnections { autoPolicy.record(speed: downloadSpeed) }
        }
        let total = chunks.last?.endOffset ?? totalSize
        onProgress?(writtenBytes, total, downloadSpeed)
    }

    private func startLogTimer() {
        logTimer?.invalidate()
        logTimer = Timer.scheduledTimer(withTimeInterval: EngineConstants.statusLogInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.syncQueue.async {
                EngineLog.manager.debug("status active=\(self.activeTasks.count)/\(self.maxConcurrent) pending=\(self.pendingCount) done=\(self.completedCount)/\(self.chunks.count) speed=\(self.downloadSpeed)/s")
            }
        }
    }

    // MARK: - Auto connection adaptation

    private func startAdaptTimer() {
        stopAdaptTimer()
        scheduleAdaptTick()
    }

    /// Self-rearming tick on the sync queue (no RunLoop dependency). Called on
    /// syncQueue; stops when auto mode is off, the download pauses or finishes.
    private func scheduleAdaptTick() {
        guard isAutoConnections, !isPaused else { return }
        adaptWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.syncQueue.async {
                self.evaluateAutoConnections()
                if self.isAutoConnections, !self.isPaused {
                    self.scheduleAdaptTick()
                }
            }
        }
        adaptWorkItem = item
        syncQueue.asyncAfter(deadline: .now() + EngineConstants.autoEvaluationInterval, execute: item)
    }

    private func stopAdaptTimer() {
        adaptWorkItem?.cancel()
        adaptWorkItem = nil
    }

    /// Applies the auto-connection policy once per evaluation tick.
    /// Call on syncQueue.
    private func evaluateAutoConnections() {
        guard isAutoConnections, !isPaused, !singleStreamMode else { return }
        let current = maxConcurrent
        let hasPending = pendingCount > 0
        guard let next = autoPolicy.evaluate(currentConnections: current, hasPending: hasPending) else { return }
        let clamped = Swift.max(1, Swift.min(next, EngineConstants.maxAutoConnections))
        guard clamped != current else { return }
        EngineLog.manager.notice("auto connections \(current) -> \(clamped)")
        maxConcurrent = clamped
        dispatchNext()
    }

    // MARK: - Helpers

    /// Splits `totalSize` bytes into fixed-size ``Chunk`` values.
    public func buildChunks(totalSize: Int64, chunkSize: Int64) -> [Chunk] {
        Chunk.chunks(totalSize: totalSize, chunkSize: chunkSize)
    }
}
