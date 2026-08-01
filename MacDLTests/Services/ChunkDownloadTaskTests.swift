import Testing
import Foundation
@testable import MacDL

@Suite struct ChunkDownloadTaskTests {
    @Test func cancelSetsCancelledFlag() {
        let url = URL(string: "https://example.com/file.bin")!
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/cancel-test-\(UUID().uuidString)")
        let task = ChunkDownloadTask(chunkIndex: 0, url: url, fileURL: dest, startOffset: 0, endOffset: 100)
        task.cancel()
        #expect(task.isCancelled == true)
    }

    @Test func pauseSetsPausedFlag() {
        let url = URL(string: "https://example.com/file.bin")!
        let dest = URL(fileURLWithPath: NSTemporaryDirectory() + "/pause-test-\(UUID().uuidString)")
        let task = ChunkDownloadTask(chunkIndex: 0, url: url, fileURL: dest, startOffset: 0, endOffset: 100)
        task.pause()
        #expect(task.isPaused == true)
        #expect(task.isCancelled == false)
    }
}
