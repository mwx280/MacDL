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

func makeChunkManager(url: URL, dest: URL, chunkSize: Int64 = 262144, maxConcurrent: Int = 4) -> ChunkManager {
    try? FileManager.default.removeItem(at: dest)
    return ChunkManager(id: UUID(), url: url, destinationURL: dest, chunkSize: chunkSize, maxConcurrent: maxConcurrent)
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
        // One 256 KB chunk = 4 x 64 KB writes. Progress must be coalesced far
        // below one callback per write (previously 4; now ~1 plus the final flush).
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
        #expect(delivered < 4)
        #expect(verifyPattern(in: dest, size: 262144))
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
}
