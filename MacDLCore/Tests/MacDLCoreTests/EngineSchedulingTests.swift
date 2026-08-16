import Testing
import Foundation
@testable import MacDLCore

// End-to-end scheduling through the real DownloadEngine: the global concurrency
// cap, FIFO queueing, promotion on completion/cap growth, and cancel/enqueue
// semantics.

@Suite(.serialized) struct EngineSchedulingTests {

    init() {
        FakeURLProtocol.reset()
        installFakeTransport()
    }

    private func makeEngine() -> DownloadEngine {
        DownloadEngine()
    }

    private func dest(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory() + name)
    }

    @Test func scheduleStartsUnderCapAndQueuesOver() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        FakeURLProtocol.perConnectionRate = 256 * 1024
        defer { FakeURLProtocol.perConnectionRate = 0 }
        let engine = makeEngine()
        engine.setMaxConcurrentDownloads(2)
        let url = URL(string: "https://fake.example/f.bin")!
        let a = UUID(), b = UUID(), c = UUID()
        #expect(engine.schedule(id: a, url: url, destinationURL: dest("/sch-a.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: []) == true)
        #expect(engine.schedule(id: b, url: url, destinationURL: dest("/sch-b.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: []) == true)
        #expect(engine.schedule(id: c, url: url, destinationURL: dest("/sch-c.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: []) == false)
        engine.cancel(id: a)
        engine.cancel(id: b)
        engine.cancel(id: c)
    }

    @Test func completionPromotesNextQueued() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        FakeURLProtocol.perConnectionRate = 256 * 1024
        defer { FakeURLProtocol.perConnectionRate = 0 }
        let engine = makeEngine()
        engine.setMaxConcurrentDownloads(1)
        let url = URL(string: "https://fake.example/f.bin")!
        let a = UUID(), b = UUID()
        var promoted: [UUID] = []
        let promLock = NSLock()
        engine.setPromotionHandler { id in promLock.lock(); promoted.append(id); promLock.unlock() }
        let semB = DispatchSemaphore(value: 0)
        engine.setCompletionHandler(for: b) { _ in semB.signal() }
        #expect(engine.schedule(id: a, url: url, destinationURL: dest("/sch-ca.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: []) == true)
        #expect(engine.schedule(id: b, url: url, destinationURL: dest("/sch-cb.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: []) == false)
        // a finishes -> b is promoted and completes.
        #expect(waitSemaphore(semB, timeout: 30))
        promLock.lock()
        let p = promoted
        promLock.unlock()
        #expect(p.contains(b))
        engine.cancel(id: a)
    }

    @Test func growingCapPromotesQueued() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        FakeURLProtocol.perConnectionRate = 256 * 1024
        defer { FakeURLProtocol.perConnectionRate = 0 }
        let engine = makeEngine()
        engine.setMaxConcurrentDownloads(1)
        let url = URL(string: "https://fake.example/f.bin")!
        let a = UUID(), b = UUID()
        var promoted: [UUID] = []
        let promLock = NSLock()
        engine.setPromotionHandler { id in promLock.lock(); promoted.append(id); promLock.unlock() }
        _ = engine.schedule(id: a, url: url, destinationURL: dest("/sch-ga.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        _ = engine.schedule(id: b, url: url, destinationURL: dest("/sch-gb.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        engine.setMaxConcurrentDownloads(2)
        promLock.lock()
        let p = promoted
        promLock.unlock()
        #expect(p.contains(b))
        engine.cancel(id: a)
        engine.cancel(id: b)
    }

    @Test func cancelDoesNotPromoteQueued() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        FakeURLProtocol.perConnectionRate = 256 * 1024
        defer { FakeURLProtocol.perConnectionRate = 0 }
        let engine = makeEngine()
        engine.setMaxConcurrentDownloads(1)
        let url = URL(string: "https://fake.example/f.bin")!
        let a = UUID(), b = UUID()
        var promoted: [UUID] = []
        let promLock = NSLock()
        engine.setPromotionHandler { id in promLock.lock(); promoted.append(id); promLock.unlock() }
        _ = engine.schedule(id: a, url: url, destinationURL: dest("/sch-xa.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        _ = engine.schedule(id: b, url: url, destinationURL: dest("/sch-xb.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        // Deleting the running download frees a slot but must not start b.
        engine.cancel(id: a)
        Thread.sleep(forTimeInterval: 0.5)
        promLock.lock()
        let p = promoted
        promLock.unlock()
        #expect(p.isEmpty)
        engine.cancel(id: b)
    }

    @Test func enqueueRegistersWithoutStarting() {
        FakeURLProtocol.virtualFileSize = 1024 * 1024
        FakeURLProtocol.perConnectionRate = 256 * 1024
        defer { FakeURLProtocol.perConnectionRate = 0 }
        let engine = makeEngine()
        engine.setMaxConcurrentDownloads(1)
        let url = URL(string: "https://fake.example/f.bin")!
        let a = UUID(), b = UUID()
        var promoted: [UUID] = []
        let promLock = NSLock()
        engine.setPromotionHandler { id in promLock.lock(); promoted.append(id); promLock.unlock() }
        _ = engine.schedule(id: a, url: url, destinationURL: dest("/sch-ea.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        // A persisted waiting download is enqueued: it must not start on its own.
        engine.enqueue(id: b, url: url, destinationURL: dest("/sch-eb.bin"), speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        Thread.sleep(forTimeInterval: 0.5)
        promLock.lock()
        let p = promoted
        promLock.unlock()
        #expect(p.isEmpty)
        engine.cancel(id: a)
        engine.cancel(id: b)
    }
}
