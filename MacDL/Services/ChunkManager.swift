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
    private var lastLogBytes: Int64 = 0
    private var lastLogTime: Date = .distantPast

    var onProgress: ((Int64, Int64, Int64) -> Void)?
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
        startLogTimer()
        syncQueue.async { self.startProbe() }
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
                self.checkDone()
                self.dispatchNext()
            }
        }
    }

    func setSpeedLimit(_ limit: Int64) {
        speedLimit = limit
        os_log("[ChunkManager] speedLimit=%lld/s", limit)
    }

    func setMaxConcurrent(_ max: Int) {
        maxConcurrent = max
        os_log("[ChunkManager] maxConcurrent=%d", max)
        syncQueue.async { self.dispatchNext() }
    }

    func pause() {
        os_log("[ChunkManager] pause")
        logTimer?.invalidate()
        logTimer = nil
        for (_, task) in activeTasks { task.pause() }
        activeTasks.removeAll()
    }

    func resume() {
        os_log("[ChunkManager] resume")
        startLogTimer()
        syncQueue.async { self.dispatchNext() }
    }

    func cancel() {
        logTimer?.invalidate()
        logTimer = nil
        for (_, task) in activeTasks { task.cancel() }
        activeTasks.removeAll()
    }

    var hasActiveTasks: Bool { !activeTasks.isEmpty }

    // MARK: - Scheduling

    private func dispatchNext() {
        let activeCount = activeTasks.count
        let canStart = max(0, maxConcurrent - activeCount)

        if canStart > 0 && !pendingIndices.isEmpty {
            var started = 0
            while started < canStart && !pendingIndices.isEmpty {
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
                setupTask(task, index: idx)
                activeTasks[idx] = task
                task.start(resumeFrom: chunks[idx].downloadedSize)
                started += 1
            }
        }

        let active = activeTasks.keys.sorted()
        print("📊 [ChunkManager] dispatch active=\(active.count)/\(maxConcurrent) pending=\(pendingIndices.count) done=\(chunks.filter { $0.status == .completed }.count)/\(chunks.count) speed=\(formatSpeed(downloadSpeed)) threads=\(maxConcurrent)")
        for idx in active {
            let s = activeTasks[idx]?.speed ?? 0
            print("  Thread #\(idx): \(formatSpeed(s))")
        }
    }

    private func checkDone() {
        let done = chunks.filter { $0.status == .completed }.count
        let failed = chunks.filter { $0.status == .failed }.count
        if done + failed >= chunks.count, !chunks.isEmpty {
            logTimer?.invalidate()
            logTimer = nil
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

    private func startLogTimer() {
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
