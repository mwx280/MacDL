import Testing
import Foundation
@testable import MacDLCore

func waitSemaphore(_ sem: DispatchSemaphore, timeout: TimeInterval = 30) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if sem.wait(timeout: .now() + 0.05) == .success { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
    return sem.wait(timeout: .now() + 0.05) == .success
}

func installFakeTransport() {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [FakeURLProtocol.self]
    ChunkDownloadTask.sessionConfigurationOverride = config
}

func makeChunkManager(url: URL, dest: URL, chunkSize: Int64 = 262144, maxConcurrent: Int = 4, mirrors: [URL] = []) -> ChunkManager {
    try? FileManager.default.removeItem(at: dest)
    return ChunkManager(id: UUID(), url: url, destinationURL: dest, chunkSize: chunkSize, maxConcurrent: maxConcurrent, mirrors: mirrors)
}

func verifyPattern(in dest: URL, size: Int64) -> Bool {
    guard let data = try? Data(contentsOf: dest), data.count == size else { return false }
    for i in data.indices {
        if data[i] != UInt8(i % 251) { return false }
    }
    return true
}

@Suite(.serialized) struct EngineTests {

    init() {
        FakeURLProtocol.reset()
        installFakeTransport()
    }

    @Test func multiChunkDownloadCompletes() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-multi.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 1024 * 1024))
    }

    @Test func pauseResumeCompletes() {
        FakeURLProtocol.virtualFileSize = 4 * 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-pause.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest)
        manager.setSpeedLimit(204_800)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        Thread.sleep(forTimeInterval: 0.3)
        manager.pause()
        Thread.sleep(forTimeInterval: 0.2)
        manager.setSpeedLimit(0)
        manager.resume()
        #expect(waitSemaphore(sem))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 4 * 1024 * 1024))
    }

    @Test func resumeProgressMonotonic() {
        FakeURLProtocol.virtualFileSize = 2 * 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-mono.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest)
        manager.setSpeedLimit(204_800)
        let lock = NSLock()
        var last: Int64 = 0
        var dipped = false
        manager.onProgress = { bytes, _, _ in
            lock.lock(); if bytes < last { dipped = true }; last = bytes; lock.unlock()
        }
        let sem = DispatchSemaphore(value: 0)
        manager.onCompletion = { _ in sem.signal() }
        manager.start()
        Thread.sleep(forTimeInterval: 0.3)
        manager.pause()
        Thread.sleep(forTimeInterval: 0.2)
        manager.resume()
        #expect(waitSemaphore(sem))
        lock.lock(); let d = dipped; lock.unlock()
        #expect(d == false)
    }

    @Test func resumeNearFullSendsBoundedRange() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-nearfull.bin")
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        let pre = Data(count: 262143)
        let fh = try! FileHandle(forWritingAtPath: dest.path)!
        fh.write(pre)
        try! fh.close()
        let task = ChunkDownloadTask(chunkIndex: 0, url: URL(string: "https://fake.example/f.bin")!, fileURL: dest, startOffset: 0, endOffset: 262144)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        task.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        task.start(resumeFrom: 262143)
        #expect(waitSemaphore(sem))
        #expect(ok)
        let range = FakeURLProtocol.requests.last?.value(forHTTPHeaderField: "Range")
        #expect(range == "bytes=262143-262143")
        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? -1
        #expect(size == 262144)
    }

    @Test func range416DoesNotDeleteFile() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-416.bin")
        try? Data(repeating: 0xAB, count: 1000).write(to: dest)
        let task = ChunkDownloadTask(chunkIndex: 0, url: URL(string: "https://fake.example/f.bin")!, fileURL: dest, startOffset: 2 * 1024 * 1024, endOffset: 3 * 1024 * 1024)
        let sem = DispatchSemaphore(value: 0)
        var failed = false
        task.onCompletion = { r in if case .failure = r { failed = true }; sem.signal() }
        task.start(resumeFrom: 0)
        #expect(waitSemaphore(sem))
        #expect(failed)
        let exists = FileManager.default.fileExists(atPath: dest.path)
        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? -1
        #expect(exists)
        #expect(size == 1000)
    }

    @Test func fileChangedAbortsResume() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-changed.bin")
        let manager = ChunkManager(id: UUID(), url: URL(string: "https://fake.example/f.bin")!, destinationURL: dest, chunkSize: 262144, maxConcurrent: 4)
        let chunks = Chunk.chunks(totalSize: 1024 * 1024, chunkSize: 262144)
        let sem = DispatchSemaphore(value: 0)
        var err: Error?
        manager.onCompletion = { r in if case .failure(let e) = r { err = e }; sem.signal() }
        FakeURLProtocol.serverTotalOverride = 2 * 1024 * 1024  // server file grew
        manager.start(withChunks: chunks, totalSize: 1024 * 1024)
        #expect(waitSemaphore(sem))
        #expect(err is DownloadError)
        #expect((err as? DownloadError) == .fileChanged)
    }

    @Test func allChunksShareOneSession() {
        // Connection reuse: every chunk must go through the same URLSession.
        let config = ChunkDownloadTask.sharedSession.configuration
        let hasFake = config.protocolClasses?.contains { $0 == FakeURLProtocol.self } ?? false
        #expect(hasFake)
        // The session is a single shared instance; a second reference is identical.
        #expect(ChunkDownloadTask.sharedSession === ChunkDownloadTask.sharedSession)
    }

    @Test func throttledConcurrentChunksIntegrity() {
        // Stress the shared-session delegate routing: many concurrent chunks,
        // throttled writes (backpressure), verify the assembled file is byte-correct.
        FakeURLProtocol.virtualFileSize = 2 * 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-shared.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest, chunkSize: 262144, maxConcurrent: 8)
        manager.setSpeedLimit(512_000)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 60))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 2 * 1024 * 1024))
    }

    @Test func chunksChangedIsThrottled() {
        // 4 chunks complete near-instantly; onChunksChanged must coalesce to far
        // fewer than 4 deliveries, and the final delivery must show all completed.
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-throttle.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest)
        let lock = NSLock()
        var count = 0
        var last: [Chunk] = []
        manager.onChunksChanged = { c in
            lock.lock()
            count += 1
            last = c
            lock.unlock()
        }
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem))
        #expect(ok)
        lock.lock()
        let delivered = count
        let finalAllCompleted = last.allSatisfy { $0.status == .completed }
        lock.unlock()
        // probe rebuild (force) + coalesced completions + final flush
        #expect(delivered < 4)
        #expect(finalAllCompleted)
        #expect(verifyPattern(in: dest, size: 1024 * 1024))
    }

    @Test func onProgressIsThrottled() {
        // A 256 KB file splits into 2 × 128 KB chunks under dynamic chunking, so
        // there are 4 × 64 KB writes. Progress must coalesce to a fixed number of
        // callbacks per chunk (finish + completion), never one per write.
        FakeURLProtocol.virtualFileSize = 262144
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-prog.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest)
        let lock = NSLock()
        var count = 0
        manager.onProgress = { _, _, _ in lock.lock(); count += 1; lock.unlock() }
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem))
        #expect(ok)
        lock.lock(); let delivered = count; lock.unlock()
        #expect(delivered < 8)
        #expect(verifyPattern(in: dest, size: 262144))
    }

    @Test func probePermanentFailureReportsError() {
        // Server unreachable from the start: the Range probe exhausts its
        // retries without ever receiving a response. The engine must still
        // report failure instead of hanging forever in the probing phase.
        FakeURLProtocol.failAllTimes = 1000
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-probefail.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest)
        let sem = DispatchSemaphore(value: 0)
        var failed = false
        manager.onCompletion = { r in if case .failure = r { failed = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 30))
        #expect(failed)
    }

    @Test func resumeAllChunksCompletedReportsDone() {
        // A download whose persisted chunks are all complete must still fire
        // the completion callback, or a crash between the last chunk write and
        // the rename would leave the task stuck at 100% forever.
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-alldone.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest)
        let completed = Chunk.chunks(totalSize: 1024 * 1024, chunkSize: 262144).map { c in
            Chunk(index: c.index, startOffset: c.startOffset, endOffset: c.endOffset, downloadedSize: c.size, status: .completed)
        }
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start(withChunks: completed, totalSize: 1024 * 1024)
        #expect(waitSemaphore(sem, timeout: 30))
        #expect(ok)
    }

    @Test func autoZeroConnectionsCompletes() {
        // maxConcurrent == 0 selects auto mode; it must still download fine.
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-auto0.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest, maxConcurrent: 0)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 30))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 1024 * 1024))
    }

    @Test func autoSmallFileUsesOneConnection() {
        // A sub-1 MiB file resolves to a single connection in auto mode.
        FakeURLProtocol.virtualFileSize = 100_000
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-autosmall.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest, maxConcurrent: 0)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 30))
        #expect(ok)
        #expect(FakeURLProtocol.peakRequests == 1)
        #expect(verifyPattern(in: dest, size: 100_000))
    }

    @Test func autoRampsConnectionsOnThrottledServer() {
        // A server that throttles each connection to 512 KiB/s: a single
        // connection would take ~16 s for 8 MiB. Auto mode must open several
        // connections and finish much faster while keeping data intact.
        FakeURLProtocol.virtualFileSize = 8 * 1024 * 1024
        FakeURLProtocol.perConnectionRate = 512 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-autothrottle.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest, maxConcurrent: 0)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        let start = Date()
        manager.start()
        #expect(waitSemaphore(sem, timeout: 60))
        let elapsed = Date().timeIntervalSince(start)
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 8 * 1024 * 1024))
        // Auto opened more connections than the 2 it started with (8 MiB < 16 MiB
        // → initial 2), proving the adaptive ramp-up happened.
        #expect(FakeURLProtocol.peakRequests >= 3)
        // Well under the ~16 s a single connection would need.
        #expect(elapsed < 10)
    }

    @Test func autoToggleMidDownloadCompletes() {
        // Switching from a fixed cap to auto mid-download must keep working.
        FakeURLProtocol.virtualFileSize = 2 * 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-autotoggle.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest, maxConcurrent: 2)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        Thread.sleep(forTimeInterval: 0.3) // probe finished, chunks running
        manager.setMaxConcurrent(0)        // switch into auto mode
        #expect(waitSemaphore(sem, timeout: 30))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 2 * 1024 * 1024))
    }

    @Test func autoWeightsInitialByLatency() {
        // A 300 ms RTT server makes a single connection RTT/window limited.
        // Auto must start with several connections immediately: the probe rate
        // (~853 KB/s) plus the latency bump lands the informed count at 4 for
        // this 8 MiB file instead of 1.
        FakeURLProtocol.virtualFileSize = 8 * 1024 * 1024
        FakeURLProtocol.latencyMs = 300
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-autolat.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest, maxConcurrent: 0)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 60))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 8 * 1024 * 1024))
        #expect(FakeURLProtocol.peakRequests >= 3)
    }

    @Test func pauseStopsRetryFromDispatching() {
        // Chunks after the probe return 429; retries are scheduled with backoff.
        // After pause, no retry may fire and no new request may be dispatched.
        FakeURLProtocol.statusOverrideAfterStart = 262144
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-pauseretry.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest, maxConcurrent: 4)
        manager.start()
        Thread.sleep(forTimeInterval: 0.4) // probe + first chunk 429s processed, retry pending
        let before = FakeURLProtocol.requests.count
        manager.pause()
        Thread.sleep(forTimeInterval: 1.5) // well past the 1 s retry backoff
        let after = FakeURLProtocol.requests.count
        #expect(after == before)
        #expect(!manager.hasActiveTasks)
    }

    @Test func range200AfterProbeFailsWithoutCorruptingFile() {
        // Chunks after the probe get 200 (server ignored Range). The chunk must
        // fail instead of writing the whole file at its offset.
        FakeURLProtocol.statusOverrideAfterStart = 200
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-range200.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest, maxConcurrent: 4)
        let sem = DispatchSemaphore(value: 0)
        var failed = false
        manager.onCompletion = { r in if case .failure = r { failed = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem))
        #expect(failed)
        // Only the probe chunk's 256 KB was written; 1-3 failed before writing.
        let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int) ?? -1
        #expect(size == 262144)
    }

    @Test func phaseStartsProbingThenDownloading() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-phase.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest)
        let lock = NSLock()
        var transitions: [Bool] = []
        manager.onPhaseChanged = { p in lock.lock(); transitions.append(p); lock.unlock() }
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem))
        #expect(ok)
        lock.lock()
        let t = transitions
        lock.unlock()
        // probing(true) first, then downloading(false) once size is known.
        #expect(t.first == true)
        #expect(t.last == false)
        #expect(t.contains(true) && t.contains(false))
    }

    @Test func singleStreamRetriesOnce() {
        // Probe gets 200 (no Range support) -> single-stream. The first
        // whole-file GET fails with a transport error; the engine must retry
        // once and then complete successfully.
        FakeURLProtocol.statusOverrideAfterStart = 0
        FakeURLProtocol.failWholeFileTimes = 1
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-singlesretry.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 20))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 1024 * 1024))
    }

    @Test func cancelStopsScheduledSingleStreamRetry() {
        // A single-stream failure schedules a retry 2 s later. Cancelling during
        // that window must prevent the retry from ever dispatching a new request.
        FakeURLProtocol.statusOverrideAfterStart = 0
        FakeURLProtocol.failWholeFileTimes = 1
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-singlescancel.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest)
        manager.start()
        // Wait for the first whole-file GET (which fails synchronously) to land.
        var deadline = Date().addingTimeInterval(5)
        while FakeURLProtocol.requests.filter({ $0.value(forHTTPHeaderField: "Range") == nil }).isEmpty,
              Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        Thread.sleep(forTimeInterval: 0.1) // let the failure + retry scheduling settle
        let before = FakeURLProtocol.requests.count
        manager.cancel()
        Thread.sleep(forTimeInterval: 2.5) // well past the 2 s retry delay
        let after = FakeURLProtocol.requests.count
        #expect(after == before)
        #expect(!manager.hasActiveTasks)
    }

    @Test func globalBucketThrottlesButStillCompletes() {
        // A global speed cap must slow the download but never deadlock or corrupt
        // the assembled file.
        ChunkDownloadTask.globalBucket.setRate(256 * 1024)
        defer { ChunkDownloadTask.globalBucket.setRate(0) }
        FakeURLProtocol.virtualFileSize = 512 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-global.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 60))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 512 * 1024))
    }

    @Test func failsOverToMirrorWhenPrimaryFails() {
        // The primary host is down; after its cooldown the download must fail over
        // to the mirror and complete byte-correct.
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        FakeURLProtocol.failingHosts = ["primary.example"]
        defer { FakeURLProtocol.failingHosts.removeAll() }
        let primary = URL(string: "https://primary.example/f.bin")!
        let mirror = URL(string: "https://mirror.example/f.bin")!
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-failover.bin")
        let manager = makeChunkManager(url: primary, dest: dest, mirrors: [mirror])
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 60))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 1024 * 1024))
        // The mirror (not the primary) must have served the bulk of the requests.
        let mirrorRequests = FakeURLProtocol.requests.filter { $0.url?.host == "mirror.example" }
        #expect(!mirrorRequests.isEmpty)
    }

    @Test func fastMirrorServesMoreChunks() {
        // The slow primary and a fast mirror: the throughput-weighted scheduler
        // must steer most chunks to the fast mirror once its throughput is known.
        FakeURLProtocol.virtualFileSize = 2 * 1024 * 1024
        FakeURLProtocol.perHostRates = ["slow.example": 100 * 1024, "fast.example": 2 * 1024 * 1024]
        defer { FakeURLProtocol.perHostRates.removeAll() }
        let slow = URL(string: "https://slow.example/f.bin")!
        let fast = URL(string: "https://fast.example/f.bin")!
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-quota.bin")
        let manager = makeChunkManager(url: slow, dest: dest, mirrors: [fast])
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 60))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 2 * 1024 * 1024))
        let fastRequests = FakeURLProtocol.requests.filter { $0.url?.host == "fast.example" }.count
        let slowRequests = FakeURLProtocol.requests.filter { $0.url?.host == "slow.example" }.count
        #expect(fastRequests > slowRequests)
    }

    @Test func rateLimitDegradesToSingleConnectionAndCompletes() {
        // A server that 429s any request beyond the first concurrent one: the
        // engine must degrade to one connection and still finish byte-correct.
        // A small latency keeps the two initial chunks in flight together so the
        // second one actually trips the rate limit.
        FakeURLProtocol.virtualFileSize = 2 * 1024 * 1024
        FakeURLProtocol.maxConcurrentRequests = 1
        FakeURLProtocol.latencyMs = 50
        defer {
            FakeURLProtocol.maxConcurrentRequests = 0
            FakeURLProtocol.latencyMs = 0
        }
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-ratelimit.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest, maxConcurrent: 0)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 60))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 2 * 1024 * 1024))
        // The server must actually have rejected at least one request (so the
        // test genuinely exercises the 429 → single-connection degradation).
        #expect(FakeURLProtocol.rateLimit429Count > 0)
    }

    @Test func softRateLimitDegradesAndCompletes() {
        // A server that throttles (not 429s) requests beyond the first one: the
        // engine must notice the slow chunk, halve its connections, and still
        // assemble the file correctly.
        FakeURLProtocol.virtualFileSize = 4 * 1024 * 1024
        FakeURLProtocol.softLimitConcurrent = 1
        FakeURLProtocol.softLimitRate = 500 * 1024
        defer {
            FakeURLProtocol.softLimitConcurrent = 0
            FakeURLProtocol.softLimitRate = 0
        }
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-softlimit.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest, maxConcurrent: 0)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 60))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 4 * 1024 * 1024))
    }

    @Test func rateLimitDegradationRecoversAndCompletes() {
        // With a fast recovery-probe base, a rate-limited server must still be
        // finished correctly, and the degradation must not be permanent: the
        // recovery probe climbs back up and trips the limit again (≥2 429s).
        // A larger file keeps the download running long enough for the probe
        // (base 0.2s) plus the adaptive evaluation (3s) to re-trip the limit.
        FakeURLProtocol.virtualFileSize = 16 * 1024 * 1024
        FakeURLProtocol.maxConcurrentRequests = 1
        FakeURLProtocol.latencyMs = 100
        ChunkManager.recoveryProbeBaseOverride = 0.2
        defer {
            FakeURLProtocol.maxConcurrentRequests = 0
            FakeURLProtocol.latencyMs = 0
            ChunkManager.recoveryProbeBaseOverride = nil
        }
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-ratelimit-recover.bin")
        let manager = makeChunkManager(url: URL(string: "https://fake.example/f.bin")!, dest: dest, maxConcurrent: 0)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 120))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 16 * 1024 * 1024))
        #expect(FakeURLProtocol.rateLimit429Count >= 2)
    }

    @Test func allSourcesDownFailsInsteadOfHanging() {
        // Both the primary and the mirror are unreachable. After cooldown and
        // failover, retries must be exhausted and the download must fail instead
        // of hanging forever (the old bug dropped the pending head when every
        // source was cooling down, and resetting retryCounts on failover let two
        // failing sources hand a chunk back and forth indefinitely).
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        FakeURLProtocol.failingHosts = ["primary.example", "mirror.example"]
        ChunkManager.sourceCooldownOverride = 0.5
        defer {
            FakeURLProtocol.failingHosts.removeAll()
            ChunkManager.sourceCooldownOverride = nil
        }
        let primary = URL(string: "https://primary.example/f.bin")!
        let mirror = URL(string: "https://mirror.example/f.bin")!
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-alldown.bin")
        let manager = makeChunkManager(url: primary, dest: dest, mirrors: [mirror])
        let sem = DispatchSemaphore(value: 0)
        var failed = false
        manager.onCompletion = { r in if case .failure = r { failed = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 60))
        #expect(failed)
    }

    @Test func ftpDownloadStreamsWholeFile() {
        // FTP has no Range support: the engine must skip the probe, stream the
        // whole file in one go, and assemble the bytes correctly.
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/eng-ftp.bin")
        let manager = makeChunkManager(url: URL(string: "ftp://ftp.example/f.bin")!, dest: dest)
        let sem = DispatchSemaphore(value: 0)
        var ok = false
        manager.onCompletion = { r in if case .success = r { ok = true }; sem.signal() }
        manager.start()
        #expect(waitSemaphore(sem, timeout: 30))
        #expect(ok)
        #expect(verifyPattern(in: dest, size: 1024 * 1024))
        // FTP must never send a Range header.
        let ranged = FakeURLProtocol.requests.filter { $0.value(forHTTPHeaderField: "Range") != nil }
        #expect(ranged.isEmpty)
    }
}
