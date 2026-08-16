import Testing
import Foundation
@testable import MacDLCore

// Priority scheduling through the real DownloadEngine: exclusive running,
// pausing other downloads, restoring them, and starting a queued priority.

@Suite(.serialized) struct EnginePriorityTests {

    init() {
        FakeURLProtocol.reset()
        installFakeTransport()
    }

    private func dest(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory() + name)
    }

    @Test func priorityPausesOthersAndRestores() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        FakeURLProtocol.perConnectionRate = 256 * 1024
        defer { FakeURLProtocol.perConnectionRate = 0 }
        let engine = DownloadEngine()
        engine.setMaxConcurrentDownloads(3)
        let url = URL(string: "https://fake.example/f.bin")!
        let a = UUID(), b = UUID(), c = UUID()
        var paused: [UUID] = []
        var resumed: [UUID] = []
        let lock = NSLock()
        engine.setPriorityPausedHandler { id in lock.lock(); paused.append(id); lock.unlock() }
        engine.setPriorityResumedHandler { id in lock.lock(); resumed.append(id); lock.unlock() }
        _ = engine.schedule(id: a, url: url, destinationURL: dest("/pr-a.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        _ = engine.schedule(id: b, url: url, destinationURL: dest("/pr-b.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        _ = engine.schedule(id: c, url: url, destinationURL: dest("/pr-c.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        engine.setPriorityDownload(a)
        lock.lock(); let p = paused; lock.unlock()
        #expect(p.sorted() == [b, c].sorted())
        engine.endPriority(excluding: nil)
        lock.lock(); let r = resumed; lock.unlock()
        #expect(r.sorted() == [b, c].sorted())
        engine.cancel(id: a)
        engine.cancel(id: b)
        engine.cancel(id: c)
    }

    @Test func priorityStartsQueuedTarget() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        FakeURLProtocol.perConnectionRate = 256 * 1024
        defer { FakeURLProtocol.perConnectionRate = 0 }
        let engine = DownloadEngine()
        engine.setMaxConcurrentDownloads(1)
        let url = URL(string: "https://fake.example/f.bin")!
        let a = UUID(), b = UUID()
        var promoted: [UUID] = []
        var paused: [UUID] = []
        let lock = NSLock()
        engine.setPromotionHandler { id in lock.lock(); promoted.append(id); lock.unlock() }
        engine.setPriorityPausedHandler { id in lock.lock(); paused.append(id); lock.unlock() }
        _ = engine.schedule(id: a, url: url, destinationURL: dest("/pr-qa.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        _ = engine.schedule(id: b, url: url, destinationURL: dest("/pr-qb.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        // b is queued (cap 1); making it priority must start it and pause a.
        engine.setPriorityDownload(b)
        lock.lock(); let pr = promoted; let pa = paused; lock.unlock()
        #expect(pr.contains(b))
        #expect(pa.contains(a))
        engine.cancel(id: a)
        engine.cancel(id: b)
    }

    @Test func endPrioritySkipsExcluded() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        FakeURLProtocol.perConnectionRate = 256 * 1024
        defer { FakeURLProtocol.perConnectionRate = 0 }
        let engine = DownloadEngine()
        engine.setMaxConcurrentDownloads(2)
        let url = URL(string: "https://fake.example/f.bin")!
        let a = UUID(), b = UUID()
        var resumed: [UUID] = []
        let lock = NSLock()
        engine.setPriorityResumedHandler { id in lock.lock(); resumed.append(id); lock.unlock() }
        _ = engine.schedule(id: a, url: url, destinationURL: dest("/pr-sa.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        _ = engine.schedule(id: b, url: url, destinationURL: dest("/pr-sb.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        engine.setPriorityDownload(a)
        engine.endPriority(excluding: b)
        lock.lock(); let r = resumed; lock.unlock()
        // b (the deleted one) must not be resumed; a is the priority (never paused).
        #expect(r.isEmpty)
        engine.cancel(id: a)
        engine.cancel(id: b)
    }
}
