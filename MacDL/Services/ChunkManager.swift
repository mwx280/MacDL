import Foundation
import os

final class ChunkManager {
    let id: UUID
    let url: URL
    let destinationURL: URL
    private(set) var chunkSize: Int64
    private(set) var totalSize: Int64 = 0
    private(set) var downloadSpeed: Int64 = 0

    private var maxConcurrent: Int
    private var speedLimit: Int64 = 0
    private var chunks: [Chunk] = []
    private var activeTasks: [Int: ChunkDownloadTask] = [:]
    private var pendingIndices: [Int] = []

    private let syncQueue = DispatchQueue(label: "com.xiaowu.chunkmanager.sync")
    private var logTimer: Timer?
    private var progressTimer: Timer?
    private var lastLogBytes: Int64 = 0
    private var lastLogTime: Date = .distantPast

    private var tokens: Double = 0
    private var lastTokenTime: Date = Date()

    var onProgress: ((Int64, Int64, Int64) -> Void)?
    var onChunksChanged: (([Chunk]) -> Void)?
    var onCompletion: ((Result<Void, Error>) -> Void)?

    init(id: UUID, url: URL, destinationURL: URL, chunkSize: Int64, maxConcurrent: Int) {
        self.id = id
        self.url = url
        self.destinationURL = destinationURL
        self.chunkSize = chunkSize
        self.maxConcurrent = maxConcurrent
    }

    // MARK: - Public control

    func start() {
        os_log("[ChunkManager] start probe chunkSize=%lld maxConcurrent=%d", chunkSize, maxConcurrent)
        startTimers()
        syncQueue.async { self.startProbe() }
    }

    func start(withChunks existing: [Chunk], totalSize: Int64) {
        self.totalSize = totalSize
        self.chunks = existing
        for i in chunks.indices where chunks[i].status != .completed {
            chunks[i].status = .pending
        }
        pendingIndices = chunks.filter { $0.status == .pending }.map(\.index)
        lastTokenTime = Date()
        let cap = speedLimit > 0 ? Double(max(speedLimit, chunkSize)) * 1.5 : Double(chunkSize) * Double(maxConcurrent)
        tokens = speedLimit > 0 ? 0 : cap
        os_log("[ChunkManager] resume chunks=%d pending=%d completed=%d total=%lld",
               chunks.count, pendingIndices.count,
               chunks.filter { $0.status == .completed }.count, totalSize)
        startTimers()
        syncQueue.async { self.dispatchNext() }
    }

    private func startProbe() {
        let probe = Chunk(index: 0, startOffset: 0, endOffset: chunkSize, downloadedSize: 0, status: .downloading)
        chunks = [probe]
        let task = ChunkDownloadTask(chunkIndex: 0, url: url, fileURL: destinationURL, startOffset: 0, endOffset: chunkSize)
        setupTask(task, index: 0)
        task.onTotalSizeKnown = { [weak self] total in
            guard let self else { return }
            self.syncQueue.async {
                guard total > 0 else { return }
                self.totalSize = total
                os_log("[ChunkManager] totalSize=%lld", total)
                let built = self.buildChunks(totalSize: total, chunkSize: self.chunkSize)
                self.chunks = built
                self.chunks[0].status = .downloading
                self.chunks[0].downloadedSize = 0
                self.pendingIndices = Array(1..<built.count)
                self.lastTokenTime = Date()
                let cap = self.speedLimit > 0 ? Double(max(self.speedLimit, self.chunkSize)) * 1.5 : Double(self.chunkSize) * Double(self.maxConcurrent)
                self.tokens = self.speedLimit > 0 ? 0 : cap
                self.onChunksChanged?(self.chunks)
                self.dispatchNext()
            }
        }
        activeTasks[0] = task
        task.start(resumeFrom: 0)
    }

    private func setupTask(_ task: ChunkDownloadTask, index: Int) {
        weak var weakTask = task
        task.onProgress = { [weak self] bytes in
            guard let self else { return }
            self.syncQueue.async {
                guard index < self.chunks.count else { return }
                self.chunks[index].downloadedSize = bytes
                self.updateProgress()
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
                let c = self.chunks[index]
                let speed = weakTask?.speed ?? 0
                self.chunks[index].downloadedSize = c.size
                print("📊 [Chunk #\(index)] ✅ speed=\(formatSpeed(speed)) size=\(c.size)")
            case .failure(let error):
                guard index < self.chunks.count else { return }
                self.chunks[index].status = .failed
                print("📊 [Chunk #\(index)] ❌ \(error.localizedDescription)")
                }
                self.updateProgress()
                self.onChunksChanged?(self.chunks)
                self.checkDone()
                self.dispatchNext()
            }
        }
    }

    func setSpeedLimit(_ limit: Int64) {
        let oldLimit = speedLimit
        speedLimit = limit
        let now = Date()
        if limit == 0 {
            tokens = Double(chunkSize) * Double(maxConcurrent)
        } else if oldLimit > 0 {
            let ratio = Double(limit) / Double(oldLimit)
            tokens = min(tokens * ratio, Double(limit))
        } else {
            tokens = min(tokens, Double(limit))
        }
        tokens = max(0, min(tokens, Double(max(limit, Int64(chunkSize))) * 1.5))
        lastTokenTime = now
        os_log("[ChunkManager] speedLimit=%lld/s old=%lld tokens=%.1f cap=%.1f", limit, oldLimit, tokens, Double(max(limit, Int64(chunkSize))) * 1.5)
        syncQueue.async { self.dispatchNext() }
    }

    func setMaxConcurrent(_ max: Int) {
        maxConcurrent = max
        os_log("[ChunkManager] maxConcurrent=%d", max)
        syncQueue.async { self.dispatchNext() }
    }

    func pause() {
        os_log("[ChunkManager] pause")
        pendingDispatch?.cancel()
        pendingDispatch = nil
        stopTimers()
        for (_, task) in activeTasks { task.pause() }
        activeTasks.removeAll()
    }

    func resume() {
        os_log("[ChunkManager] resume")
        startTimers()
        syncQueue.async { self.dispatchNext() }
    }

    func cancel() {
        pendingDispatch?.cancel()
        pendingDispatch = nil
        stopTimers()
        for (_, task) in activeTasks { task.cancel() }
        activeTasks.removeAll()
    }

    var hasActiveTasks: Bool { !activeTasks.isEmpty }

    // MARK: - Scheduling

    private var pendingDispatch: DispatchWorkItem?

    private func dispatchNext() {
        let now = Date()
        if speedLimit > 0 {
            let elapsed = now.timeIntervalSince(lastTokenTime)
            if elapsed > 0 {
                tokens += Double(speedLimit) * elapsed
                let cap = Double(max(speedLimit, chunkSize)) * 1.5
                tokens = min(tokens, cap)
                lastTokenTime = now
            }
        } else {
            tokens = Double(chunkSize) * Double(maxConcurrent)
        }

        let activeCount = activeTasks.count
        let maxBurst: Int
        if speedLimit > 0 {
            maxBurst = max(1, min(maxConcurrent, Int(Double(speedLimit) / Double(chunkSize)) + 1))
        } else {
            maxBurst = maxConcurrent
        }
        let canStart = min(max(0, maxConcurrent - activeCount), maxBurst)

        var waited = false
        if canStart > 0 && !pendingIndices.isEmpty {
            var started = 0
            while started < canStart && !pendingIndices.isEmpty {
                if speedLimit > 0, tokens < Double(chunkSize) {
                    if !waited && activeCount == 0 {
                        let missing = Double(chunkSize) - tokens
                        let wait = max(missing / Double(speedLimit), 0.05)
                        pendingDispatch?.cancel()
                        let item = DispatchWorkItem { [weak self] in self?.dispatchNext() }
                        pendingDispatch = item
                        syncQueue.asyncAfter(deadline: .now() + wait, execute: item)
                        waited = true
                        print("📊 [ChunkManager] wait missing=\(Int(missing)) wait=\(String(format: "%.2f", wait))s tokens=\(Int(tokens))")
                    }
                    break
                }
                let idx = pendingIndices.removeFirst()
                guard idx < chunks.count, chunks[idx].status != .completed else { continue }
                chunks[idx].status = .downloading
                tokens = max(0, tokens - Double(chunkSize))

                let chunk = chunks[idx]
                let task = ChunkDownloadTask(
                    chunkIndex: idx,
                    url: url,
                    fileURL: destinationURL,
                    startOffset: chunk.startOffset,
                    endOffset: chunk.endOffset
                )
                setupTask(task, index: idx)
                activeTasks[idx] = task
                task.start(resumeFrom: chunks[idx].downloadedSize)
                started += 1
            }
        }

        let active = activeTasks.keys.sorted()
        print("📊 [ChunkManager] dispatch active=\(active.count)/\(maxConcurrent) pending=\(pendingIndices.count) done=\(chunks.filter { $0.status == .completed }.count)/\(chunks.count) speed=\(formatSpeed(downloadSpeed)) threads=\(maxConcurrent) maxBurst=\(maxBurst) tokens=\(Int(tokens))")
        for idx in active {
            let s = activeTasks[idx]?.speed ?? 0
            print("  Thread #\(idx): \(formatSpeed(s))")
        }
    }

    private func checkDone() {
        let done = chunks.filter { $0.status == .completed }.count
        let failed = chunks.filter { $0.status == .failed }.count
        if done + failed >= chunks.count, !chunks.isEmpty {
            stopTimers()
            if failed > 0 {
                onCompletion?(.failure(DownloadError.cancelled))
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
        if elapsed >= 1.0 {
            downloadSpeed = Int64(Double(written - lastLogBytes) / elapsed)
            lastLogTime = now
            lastLogBytes = written
        }
        let total = chunks.last?.endOffset ?? totalSize
        onProgress?(written, total, downloadSpeed)
    }

    private func startTimers() {
        logTimer?.invalidate()
        logTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.syncQueue.async {
                let active = self.activeTasks.keys.sorted()
                print("📊 [ChunkManager] status active=\(active.count)/\(self.maxConcurrent) pending=\(self.pendingIndices.count) done=\(self.chunks.filter { $0.status == .completed }.count)/\(self.chunks.count) speed=\(formatSpeed(self.downloadSpeed)) threads=\(self.maxConcurrent)")
                for idx in active {
                    let s = self.activeTasks[idx]?.speed ?? 0
                    print("  Thread #\(idx): \(formatSpeed(s))")
                }
            }
        }
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.syncQueue.async { self.updateProgress() }
        }
    }

    private func stopTimers() {
        logTimer?.invalidate()
        logTimer = nil
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - Helpers

    func buildChunks(totalSize: Int64, chunkSize: Int64) -> [Chunk] {
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
