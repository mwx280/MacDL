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
    private let isFTP: Bool
    private var autoPolicy = AutoConnectionPolicy()
    private var adaptWorkItem: DispatchWorkItem?
    private var probeStartTime: Date?
    private var probeDataStartTime: Date?
    private var measuredRTT: TimeInterval = 0
    private var rttMeasured = false
    private var historyRTT: TimeInterval?
    private var historyBandwidth: Int64?
    private var speedLimit: Int64 = 0
    private var chunks: [Chunk] = []
    private var sources: [Source] = []
    private var chunkSource: [Int: Int] = [:]
    private var chunkDispatchTime: [Int: Date] = [:]
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
    private var recoveryAttempts = 0
    private var recoveryWorkItem: DispatchWorkItem?
    // Last moment the aggregate actually received/wrote bytes (not when a task
    // was merely dispatched or failed). Drives the "retrying" state: a retryable
    // network failure with no recent bytes means the link is down, not a single
    // chunk hiccup.
    private var lastByteTime = Date()
    // Chunk indices cancelled by the stall watchdog; their failures must not be
    // fed to the adaptive connection policy or the source cooldown counter.
    private var stalledChunks = Set<Int>()
    private var stallCheckWorkItem: DispatchWorkItem?
    private var isStallChecking = false
    // Current "retrying after a stall" state, edge-triggered via onRetrying.
    private var isRetrying = false

    private let maxRetries = EngineConstants.maxChunkRetries
    private let bucket = TokenBucket(rate: 0)
    /// Test hook overriding the rate-limit recovery-probe base delay.
    nonisolated(unsafe) static var recoveryProbeBaseOverride: TimeInterval?
    /// Test hook overriding the source cooldown interval.
    nonisolated(unsafe) static var sourceCooldownOverride: TimeInterval?
    /// Test hook overriding the stall timeout.
    nonisolated(unsafe) static var stallTimeoutOverride: TimeInterval?
    /// Test hook overriding the stall-check cadence.
    nonisolated(unsafe) static var stallCheckIntervalOverride: TimeInterval?

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
    /// Edge-triggered: `true` while a stalled transfer is being re-established,
    /// `false` once bytes flow again or the download ends/pauses. Lets the app
    /// show "network interrupted, retrying" instead of a frozen counter.
    public var onRetrying: ((Bool) -> Void)?
    /// Returns whether the local network link is currently down. Set by the
    /// engine from reachability. While it returns true, the manager holds
    /// chunks instead of burning retries, and waits for `networkRecovered()`.
    public var isNetworkDown: (() -> Bool)?
    /// Returns the engine's current per-download connection budget (the global
    /// cap split across running downloads). Set by the engine; read on syncQueue.
    /// Nil for a standalone manager, which then uses `maxAutoConnections`.
    public var connectionBudgetLimit: (() -> Int)?

    /// The connection cap in effect for this download: the engine's budget share
    /// when attached, otherwise the engine-wide max.
    private var connectionBudgetCap: Int {
        connectionBudgetLimit?() ?? EngineConstants.maxAutoConnections
    }

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
        self.isFTP = url.scheme?.lowercased() == "ftp"
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
            self.startStallCheck()
            if self.isFTP {
                // FTP has no Range support: skip the probe and stream the whole
                // file in one go.
                self.enterSingleStream()
            } else {
                self.onPhaseChanged?(true)
                self.startProbe()
            }
        }
    }

    /// Resumes from a persisted chunk list; completed chunks are never re-fetched.
    public func start(withChunks existing: [Chunk], totalSize: Int64) {
        EngineLog.manager.notice("resume chunks=\(existing.count) pending=\(existing.filter { $0.status != .completed }.count) completed=\(existing.filter { $0.status == .completed }.count) total=\(totalSize)")
        startLogTimer()
        syncQueue.async {
            self.singleStreamRetries = 0
            self.onPhaseChanged?(false)
            self.startStallCheck()
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
                    self.connectionBudgetCap))
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
        let probeSize = chunks.first?.size ?? chunkSize
        let dynamicChunkSize = ChunkingPolicy.chunkSize(
            totalSize: total, rtt: historyRTT ?? measuredRTT,
            singleConnRate: historyBandwidth ?? 0)
        if dynamicChunkSize != chunkSize {
            chunkSize = dynamicChunkSize
            onChunkSizeChanged?(dynamicChunkSize)
        }
        // The probe only fetched the first `probeSize` bytes (the original chunk
        // size). Keep chunk 0 bounded to that range so its already-downloaded
        // bytes complete cleanly even when the dynamic size grew; the larger
        // size applies to the remaining chunks.
        let built = buildChunks(totalSize: total, probeSize: probeSize, chunkSize: chunkSize)
        chunks = built
        completedCount = 0
        failedCount = 0
        writtenBytes = 0
        chunks[0].status = .downloading
        chunks[0].downloadedSize = 0
        pendingIndices = Array(1..<built.count)
        pendingHead = 0
        if isAutoConnections {
            if let bw = historyBandwidth, !isThrottled {
                maxConcurrent = max(1, min(
                    AutoConnectionPolicy.informedInitialConnectionCount(
                        singleConnRate: bw, fileSize: total, rtt: historyRTT ?? measuredRTT),
                    connectionBudgetCap))
                EngineLog.manager.notice("auto historical connections=\(maxConcurrent) bw=\(bw)")
            } else {
                maxConcurrent = max(1, min(
                    AutoConnectionPolicy.initialConnectionCount(fileSize: total, supportsResume: true, rtt: measuredRTT),
                    connectionBudgetCap))
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
                let prev = self.chunks[index].downloadedSize
                if bytes > prev {
                    self.lastByteTime = Date()
                }
                self.writtenBytes += bytes - prev
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
                    self.stalledChunks.remove(index)
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
                            // A completed chunk proves the server is serving us
                            // again: reset the rate-limit recovery backoff so a
                            // transient 429 does not leave the download stuck at
                            // a low connection count for a growing delay.
                            self.recoveryAttempts = 0
                            if let start = self.chunkDispatchTime.removeValue(forKey: index) {
                                let elapsed = Date().timeIntervalSince(start)
                                if elapsed > 0.05 {
                                    let rate = Int64(Double(self.chunks[index].size) / elapsed)
                                    self.sources[si].recordThroughput(rate)
                                }
                            }
                        }
                        EngineLog.manager.notice("chunk \(index) completed")
                        // The probe chunk doubles as a single-connection speed
                        // sample: refine the initial count from its measured
                        // throughput instead of climbing one step at a time.
                        // Skip it under a speed limit, where the measured rate is
                        // the throttled write rate, not the link's capability.
                        if self.isAutoConnections, index == 0, self.rttMeasured, !self.isThrottled {
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
                    let isStall = self.stalledChunks.remove(index) != nil
                    willRetry = self.handleChunkFailure(index, error: error, isStall: isStall)
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
    private func handleChunkFailure(_ index: Int, error: Error, isStall: Bool = false) -> Bool {
        guard index < chunks.count else { return false }
        // A 429 means the server rate-limits concurrent requests. Degrade to a
        // single connection immediately instead of letting the adaptive policy
        // thrash between retries and more 429s.
        if (error as? DownloadError) == .httpStatus(429) {
            handleRateLimit()
        }
        // Feed retryable failures to the auto policy so a stressed server stops
        // being probed upward. Only server responses (429/5xx) are genuine
        // stress signals; transport failures (URLError / DownloadError.network,
        // which also covers stall-cancels) mean the LINK is down — freezing the
        // connection count for those would leave the adaptive engine stuck at a
        // low count after the link returns.
        if isAutoConnections, (error as? DownloadError)?.isRetryable != false, !isNetworkFailure(error) {
            autoPolicy.recordFailure()
        }
        if let dlError = error as? DownloadError, !dlError.isRetryable {
            lastError = error
            writtenBytes -= chunks[index].downloadedSize
            chunks[index].status = .failed
            failedCount += 1
            markChunkDirty(index)
            chunkSource[index] = nil
            chunkDispatchTime[index] = nil
            EngineLog.manager.error("chunk \(index) failed permanently (\(dlError.errorDescription ?? "?"))")
            return false
        }
        // While the local link is down (reachability), hold the chunk instead of
        // burning a retry: requeue it pending without counting the attempt, and
        // let the recovery kick re-dispatch it. The download shows the retrying
        // state until the link returns. This must run before the source failover
        // below: a dropped local link is a global fault, not a source-specific
        // one, so it must not cool down / fail over the source.
        if isNetworkFailure(error), isNetworkDown?() == true {
            writtenBytes -= chunks[index].downloadedSize
            chunks[index].status = .pending
            markChunkDirty(index)
            enqueuePending(index)
            setRetrying(true)
            EngineLog.manager.notice("chunk \(index) held, network is down")
            return false
        }
        // Failover: when the chunk's source goes into cooldown and another source
        // is available, requeue the chunk so the next dispatch picks the healthy
        // source instead of the failing one. Returns false (no backoff timer) so
        // the caller re-dispatches now. Without an alternative source the chunk
        // keeps the normal retry path (and fails once retries are exhausted).
        // Stalls are excluded: a dropped local link is not a source-specific
        // fault, so it must not cool the source down.
        if sources.count > 1, let si = chunkSource[index], !isStall {
            let cooldown = Self.sourceCooldownOverride ?? EngineConstants.sourceCooldownInterval
            sources[si].recordFailure(now: Date(),
                                      threshold: EngineConstants.sourceFailureThreshold,
                                      cooldown: cooldown,
                                      cooldownCap: EngineConstants.sourceCooldownCap)
            if !sources[si].isAvailable() {
                let hasAlternative = sources.enumerated().contains { $0.offset != si && $0.element.isAvailable() }
                if hasAlternative {
                    EngineLog.manager.warning("source \(si) cooled down, failing chunk \(index) over")
                    chunkSource[index] = nil
                    chunkDispatchTime[index] = nil
                    // Do NOT reset retryCounts here: keep the count across sources
                    // so two failing sources can't hand the chunk back and forth
                    // forever. A failover is just another attempt, and the chunk
                    // must still give up once retries are exhausted.
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
            chunkSource[index] = nil
            chunkDispatchTime[index] = nil
            EngineLog.manager.error("chunk \(index) failed permanently after \(self.maxRetries) attempts")
            return false
        }
        retryCounts[index] = attempt
        writtenBytes -= chunks[index].downloadedSize
        chunks[index].status = .pending
        markChunkDirty(index)
        enqueuePending(index)
        // A retryable transport failure with no bytes flowing recently means the
        // link is down (e.g. Wi-Fi turned off): surface the retrying state so
        // the user sees "network interrupted, retrying" instead of a frozen
        // counter. A single chunk hiccup among flowing ones is not shown.
        if isNetworkFailure(error), Date().timeIntervalSince(lastByteTime) > EngineConstants.retryingGraceInterval {
            setRetrying(true)
        }
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

    /// True for transport-level failures (URLError / NSURLErrorDomain /
    /// DownloadError.network). HTTP status errors (429/5xx) are server
    /// responses, not a dead link, and must not flip the row into the "network
    /// interrupted" state. URLSession bridges the delegate error to NSError, so
    /// the domain check is what catches it in practice.
    private func isNetworkFailure(_ error: Error) -> Bool {
        if error is URLError { return true }
        if case .network? = error as? DownloadError { return true }
        if let ns = error as NSError?, ns.domain == NSURLErrorDomain { return true }
        return false
    }

    /// Degrades to a single connection when the server signals hard rate-limiting
    /// (HTTP 429), and stops the adaptive timer so it stays there for this
    /// session. The adaptive policy's "try more connections" assumption is wrong
    /// for such servers — the second concurrent request is rejected outright.
    private func handleRateLimit() {
        degradeConcurrency(to: 1)
    }

    /// Lowers the connection cap, locks the adaptive policy at that ceiling and
    /// stops the adaptive timer so it does not probe back up into the limit.
    /// A recovery probe is scheduled with exponential backoff so a transient
    /// limit does not permanently strand the download at a low count, while a
    /// persistently limiting server is only re-probed ever more rarely.
    private func degradeConcurrency(to count: Int) {
        guard isAutoConnections, maxConcurrent > count else { return }
        EngineLog.manager.warning("degrading connections \(maxConcurrent) -> \(count)")
        maxConcurrent = count
        stopAdaptTimer()
        autoPolicy.forceConcurrencyCeiling(count)
        scheduleRecoveryProbe()
    }

    /// After a rate-limit degradation, re-enables adaptive connections once the
    /// backoff delay has passed, so the download can climb back up if the server
    /// has recovered. Each degradation doubles the wait, capped at
    /// `rateLimitRecoveryCap`, so a persistently limiting server is probed less
    /// and less often.
    private func scheduleRecoveryProbe() {
        recoveryWorkItem?.cancel()
        recoveryAttempts += 1
        let base = Self.recoveryProbeBaseOverride ?? EngineConstants.rateLimitRecoveryBase
        let delay = min(base * pow(2.0, Double(recoveryAttempts - 1)),
                        EngineConstants.rateLimitRecoveryCap)
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.recoveryWorkItem = nil
            guard self.isAutoConnections, !self.isPaused,
                  self.maxConcurrent < EngineConstants.maxAutoConnections else { return }
            EngineLog.manager.notice("rate-limit recovery probe after \(Int(delay))s, re-enabling adaptive connections")
            self.autoPolicy.reset()
            self.startAdaptTimer()
        }
        recoveryWorkItem = item
        syncQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Updates the byte/second throttle shared by all chunks of this download.
    public func setSpeedLimit(_ limit: Int64) {
        EngineLog.manager.notice("speedLimit=\(limit)/s")
        syncQueue.async {
            self.speedLimit = limit
            self.updateBucket()
            // A speed-limit change invalidates the adaptive policy's measurements
            // (the observed speed was the old throttle's, not the link's).
            if self.isAutoConnections {
                self.autoPolicy.reset()
                self.evaluateAutoConnections()
            }
        }
    }

    /// Called when the global speed cap changes, so adaptive connections
    /// re-converge immediately instead of waiting for the periodic re-probe.
    public func onSpeedLimitChanged() {
        syncQueue.async {
            guard self.isAutoConnections else { return }
            self.autoPolicy.reset()
            self.evaluateAutoConnections()
        }
    }

    /// Called when the global connection budget share changes (a download
    /// started or finished). Clamps the connection count down to the new share
    /// so the aggregate never exceeds the budget; a later re-probe climbs back
    /// when the share grows.
    public func onConnectionBudgetChanged() {
        syncQueue.async {
            guard self.isAutoConnections else { return }
            let cap = self.connectionBudgetCap
            if self.maxConcurrent > cap {
                EngineLog.manager.notice("budget cap \(cap), clamping connections \(self.maxConcurrent) -> \(cap)")
                self.maxConcurrent = max(1, cap)
                self.dispatchNext()
            }
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
                        self.connectionBudgetCap))
                    self.startAdaptTimer()
                    EngineLog.manager.notice("auto connections enabled, initial=\(self.maxConcurrent)")
                } else {
                    // Re-selecting auto gives the download a fresh chance.
                    self.autoPolicy.resetCircuitBreaker()
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
            self.autoPolicy.resetCircuitBreaker()
            self.stopStallCheck()
            self.setRetrying(false)
            self.bucket.stop()
            // Freeze scheduling: cancel pending retries and clear the queue so
            // nothing can start new chunk tasks while paused.
            for (_, item) in self.retryWorkItems { item.cancel() }
            self.retryWorkItems.removeAll()
            self.singleStreamRetryItem?.cancel()
            self.singleStreamRetryItem = nil
            self.recoveryWorkItem?.cancel()
            self.recoveryWorkItem = nil
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
            self.setRetrying(false)
            self.startStallCheck()
            if self.isAutoConnections {
                self.autoPolicy.resetCircuitBreaker()
                self.startAdaptTimer()
            }
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
            self.stopStallCheck()
            self.setRetrying(false)
            self.bucket.stop()
            for (_, item) in self.retryWorkItems { item.cancel() }
            self.retryWorkItems.removeAll()
            self.singleStreamRetryItem?.cancel()
            self.singleStreamRetryItem = nil
            self.recoveryWorkItem?.cancel()
            self.recoveryWorkItem = nil
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

    /// Whether the adaptive connection policy is currently frozen by retryable
    /// failures (429/5xx). Test hook: transport failures must never freeze it.
    var isAutoPolicyFrozen: Bool {
        syncQueue.sync { autoPolicy.isFrozen }
    }

    /// Whether the adaptive policy's circuit breaker has tripped. Test hook.
    var isAutoPolicyTripped: Bool {
        syncQueue.sync { autoPolicy.isTripped }
    }

    /// The current adaptive connection cap. Test hook: lets tests observe the
    /// cold-start decision without reimplementing the probe.
    var currentMaxConcurrent: Int {
        syncQueue.sync { maxConcurrent }
    }
    // MARK: - Scheduling

    /// True while a speed limit (this download's own, or the shared global cap)
    /// is in effect. The adaptive connection policy uses this to skip rate-based
    /// cold-start estimates; the running adaptation keys off observed no-gain
    /// probes instead, since a shared global cap has no static per-download rate.
    private var isThrottled: Bool {
        speedLimit > 0 || ChunkDownloadTask.globalBucket.currentRate > 0
    }

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
                if bytes > self.singleStreamBytes {
                    self.lastByteTime = Date()
                }
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
                    self.setRetrying(false)
                    self.onProgress?(self.singleStreamTotal, self.singleStreamTotal, self.downloadSpeed)
                    self.onCompletion?(.success(()))
                case .failure(let error):
                    // Give a slow/flaky server one quick retry before failing.
                    // Never retry a user cancel, and skip when paused.
                    let isCancelled = (error as? DownloadError) == .cancelled
                    // While the local link is down, hold the stream instead of
                    // burning one of the few single-stream retries against a dead
                    // network. networkRecovered() re-enters the stream.
                    if !isCancelled, !self.isPaused, self.isNetworkFailure(error), self.isNetworkDown?() == true {
                        self.setRetrying(true)
                        EngineLog.manager.notice("single-stream held, network is down")
                        return
                    }
                    if !isCancelled, !self.isPaused, self.singleStreamRetries < EngineConstants.maxSingleStreamRetries {
                        self.singleStreamRetries += 1
                        // A single-stream failure means the whole transfer is
                        // down: surface the retrying state during the retry.
                        if self.isNetworkFailure(error) {
                            self.setRetrying(true)
                        }
                        EngineLog.manager.warning("single-stream failed (\(error.localizedDescription)), retry \(self.singleStreamRetries)/\(EngineConstants.maxSingleStreamRetries)")
                        self.bucket.reset(rate: self.speedLimit > 0 ? Double(self.speedLimit) : 0)
                        // Keep the retry cancellable so pause()/cancel() can stop it —
                        // otherwise a stale retry would restart the download after the
                        // user asked to stop.
                        let item = DispatchWorkItem { [weak self] in self?.enterSingleStream() }
                        self.singleStreamRetryItem = item
                        self.syncQueue.asyncAfter(deadline: .now() + EngineConstants.singleStreamRetryDelay, execute: item)
                    } else {
                        self.setRetrying(false)
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
            if downloadSpeed > 0, isRetrying { setRetrying(false) }
        }
        let total = singleStreamTotal > 0 ? singleStreamTotal : 0
        onProgress?(singleStreamBytes, total, downloadSpeed)
    }

    private func dispatchNext() {
        guard !isPaused else { return }
        // While the local link is down, hold every pending chunk: dispatching
        // would only fail again. The engine's reachability recovery kick calls
        // `networkRecovered()` when the link returns.
        if isNetworkDown?() == true { return }
        let activeCount = activeTasks.count
        let canStart = max(0, maxConcurrent - activeCount)
        if canStart > 0, pendingHead < pendingIndices.count {
            var started = 0
            while started < canStart, pendingHead < pendingIndices.count {
                let idx = pendingIndices[pendingHead]
                guard idx < chunks.count, chunks[idx].status != .completed else {
                    pendingHead += 1
                    continue
                }
                // Weighted round-robin across healthy sources: faster sources
                // (higher EWMA throughput) serve more chunks, and cooling-down
                // sources get none. An unmeasured mirror serves at most one
                // trial chunk so a slow mirror can't eat half the file before
                // its throughput is sampled.
                let throughputs = sources.map(\.avgThroughput)
                var activePerSource = Array(repeating: 0, count: sources.count)
                for idx in activeTasks.keys {
                    if let si = chunkSource[idx] { activePerSource[si] += 1 }
                }
                let available = sources.indices.map { i -> Bool in
                    guard sources[i].isAvailable() else { return false }
                    if i > 0, !sources[i].hasSampledThroughput, activePerSource[i] > 0 { return false }
                    return true
                }
                guard let si = sourceScheduler.pick(throughputs: throughputs, available: available) else {
                    // No source is usable right now: leave the head in place and
                    // let the cooldown timer re-enter dispatch when one recovers.
                    scheduleSourceRecovery()
                    break
                }
                pendingHead += 1
                chunkSource[idx] = si
                chunkDispatchTime[idx] = Date()
                // A failover re-probe (chunk 0 dispatched while the size is still
                // unknown) must restart the RTT clock, otherwise the measured RTT
                // includes the failed attempts on the previous source.
                if idx == 0, totalSize == 0 {
                    probeStartTime = Date()
                    probeDataStartTime = nil
                }
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

    // MARK: - Stall detection

    /// Starts the periodic stall watchdog. Call on syncQueue.
    private func startStallCheck() {
        guard !isStallChecking else { return }
        isStallChecking = true
        scheduleStallCheck()
    }

    /// Stops the stall watchdog. Call on syncQueue.
    private func stopStallCheck() {
        isStallChecking = false
        stallCheckWorkItem?.cancel()
        stallCheckWorkItem = nil
    }

    /// Self-rearming tick on the sync queue (no RunLoop dependency). Called on
    /// syncQueue; stops when the download pauses, cancels or finishes.
    private func scheduleStallCheck() {
        guard isStallChecking else { return }
        stallCheckWorkItem?.cancel()
        let interval = Self.stallCheckIntervalOverride ?? EngineConstants.stallCheckInterval
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.syncQueue.async {
                self.checkForStalls()
                if self.isStallChecking {
                    self.scheduleStallCheck()
                }
            }
        }
        stallCheckWorkItem = item
        syncQueue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    /// A task that has received or written no bytes for `stallTimeout` is
    /// treated as a dropped connection (silent/half-open): cancel it so the
    /// chunk retries instead of waiting out the URLSession request timeout.
    /// Detection is per-task so a freshly dispatched request gets a full window
    /// of its own, but only while the DOWNLOAD is silent: a speed limit
    /// throttles every chunk through a shared token bucket, so an individual
    /// chunk can legitimately wait longer than `stallTimeout` between writes
    /// while the transfer keeps progressing. A local network drop stops the
    /// whole download at once; a speed limit does not. Call on syncQueue.
    private func checkForStalls() {
        guard !isPaused else { return }
        let timeout = Self.stallTimeoutOverride ?? EngineConstants.stallTimeout
        let downloadQuiet = Date().timeIntervalSince(lastByteTime) > timeout
        guard downloadQuiet else { return }
        var cancelled = false
        for (index, task) in activeTasks where task.isIdle(for: timeout) {
            EngineLog.manager.warning("chunk \(index) stalled (no activity for \(Int(timeout))s), cancelling")
            stalledChunks.insert(index)
            task.cancelAsStall()
            cancelled = true
        }
        if let sst = singleStreamTask, sst.isIdle(for: timeout) {
            EngineLog.manager.warning("single-stream stalled, cancelling")
            sst.cancelAsStall()
            cancelled = true
        }
        if cancelled { setRetrying(true) }
    }

    /// Edge-triggered "retrying after a stall" state, so the app is not spammed
    /// with repeated callbacks. Call on syncQueue.
    private func setRetrying(_ value: Bool) {
        guard isRetrying != value else { return }
        isRetrying = value
        onRetrying?(value)
    }

    /// Called by the engine when the network link comes back up: re-dispatches
    /// the chunks that were held while it was down, or re-enters a held
    /// single-stream transfer.
    public func networkRecovered() {
        syncQueue.async {
            guard !self.isPaused else { return }
            if self.singleStreamMode, self.singleStreamTask == nil {
                self.singleStreamRetryItem?.cancel()
                self.singleStreamRetryItem = nil
                self.enterSingleStream()
            } else {
                self.dispatchNext()
            }
        }
    }

    private func checkDone() {
        let done = completedCount
        let failed = failedCount
        guard done + failed >= chunks.count, !chunks.isEmpty else { return }
        logTimer?.invalidate()
        logTimer = nil
        stopAdaptTimer()
        stopStallCheck()
        setRetrying(false)
        recoveryWorkItem?.cancel()
        recoveryWorkItem = nil
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
        guard totalSize > 0 else { return }
        let host = url.host ?? ""
        guard !host.isEmpty else { return }
        // A throttled download's measured speed is the cap, not the link's
        // capability; recording it would poison future cold-start estimates.
        guard !isThrottled else { return }
        // Use the recent throughput (not totalSize/elapsed, which overstates a
        // resumed download that only fetched the remaining bytes this session).
        let bandwidth = downloadSpeed
        guard bandwidth > 0 else { return }
        // Only update RTT when a probe actually measured one; a resumed download
        // has no probe, and writing 0 would drag the host's EWMA down.
        if measuredRTT > 0 {
            SourceHistoryStore.shared.record(host: host, bandwidth: bandwidth,
                                             rtt: measuredRTT, success: success,
                                             supportsRange: serverSupportsResume)
        } else if let existing = SourceHistoryStore.shared.history(for: host), existing.sampleCount > 0 {
            SourceHistoryStore.shared.record(host: host, bandwidth: bandwidth,
                                             rtt: existing.avgRTT, success: success,
                                             supportsRange: serverSupportsResume)
        }
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
            // Bytes are flowing again after a stall: drop the retrying state.
            if downloadSpeed > 0, isRetrying { setRetrying(false) }
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
        let wasTripped = autoPolicy.isTripped
        guard let next = autoPolicy.evaluate(currentConnections: current, hasPending: hasPending) else { return }
        let clamped = Swift.max(1, Swift.min(next, EngineConstants.maxAutoConnections, connectionBudgetCap))
        if autoPolicy.isTripped, !wasTripped {
            EngineLog.manager.warning("adaptive connections tripped, locking at \(clamped)")
            stopAdaptTimer()
        }
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

    /// Splits the file after the probe: chunk 0 keeps the probe's range
    /// (`probeSize`, the original chunk size), and the remaining bytes split at
    /// the (possibly dynamic) `chunkSize`.
    private func buildChunks(totalSize: Int64, probeSize: Int64, chunkSize: Int64) -> [Chunk] {
        let firstEnd = min(max(0, probeSize), totalSize)
        var result = [Chunk(index: 0, startOffset: 0, endOffset: firstEnd,
                            downloadedSize: 0, status: .pending)]
        let cs = max(Int64(1), chunkSize)
        var offset = firstEnd
        var index = 1
        while offset < totalSize {
            let end = min(offset + cs, totalSize)
            result.append(Chunk(index: index, startOffset: offset, endOffset: end,
                                downloadedSize: 0, status: .pending))
            offset = end
            index += 1
        }
        return result
    }
}
