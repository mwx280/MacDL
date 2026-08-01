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
        let chunks = Download(filename: "f.bin", url: "https://fake.example/f.bin", totalSize: 1024 * 1024).buildChunks()
        let sem = DispatchSemaphore(value: 0)
        var err: Error?
        manager.onCompletion = { r in if case .failure(let e) = r { err = e }; sem.signal() }
        FakeURLProtocol.serverTotalOverride = 2 * 1024 * 1024  // server file grew
        manager.start(withChunks: chunks, totalSize: 1024 * 1024)
        #expect(waitSemaphore(sem))
        #expect(err is DownloadError)
        #expect((err as? DownloadError) == .fileChanged)
    }
}
