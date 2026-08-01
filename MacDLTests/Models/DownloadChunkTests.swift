import Testing
import Foundation
@testable import MacDL

@Suite struct DownloadChunkTests {
    private func makeDownload(totalSize: Int64, downloadedSize: Int64 = 0, chunks: [Chunk] = []) -> Download {
        Download(filename: "t.bin", url: "https://e.com/t.bin", totalSize: totalSize,
                 downloadedSize: downloadedSize, chunkSize: 256, chunks: chunks)
    }

    @Test func buildChunksSplitsEvenly() {
        let chunks = makeDownload(totalSize: 1000).buildChunks()
        #expect(chunks.count == 4)
        #expect(chunks[0].startOffset == 0)
        #expect(chunks[0].endOffset == 256)
        #expect(chunks[1].startOffset == 256)
        #expect(chunks[3].endOffset == 1000)
        #expect(chunks.allSatisfy { $0.status == .pending })
    }

    @Test func buildChunksEmptyWhenTotalZero() {
        let chunks = makeDownload(totalSize: 0).buildChunks()
        #expect(chunks.isEmpty)
    }

    @Test func ensureChunksMarksProgress() {
        let chunks = makeDownload(totalSize: 1000, downloadedSize: 100).ensureChunks()
        #expect(chunks.count == 4)
        #expect(chunks[0].downloadedSize == 100)
        #expect(chunks[0].status == .pending)
        #expect(chunks[1].downloadedSize == 0)
    }

    @Test func ensureChunksMarksCompleted() {
        let chunks = makeDownload(totalSize: 1000, downloadedSize: 1000).ensureChunks()
        #expect(chunks.count == 4)
        #expect(chunks.allSatisfy { $0.status == .completed })
        #expect(chunks.allSatisfy { $0.downloadedSize == $0.size })
    }

    @Test func ensureChunksKeepsExisting() {
        let existing = [Chunk(index: 0, startOffset: 0, endOffset: 256, downloadedSize: 128, status: .downloading)]
        let chunks = makeDownload(totalSize: 1000, chunks: existing).ensureChunks()
        #expect(chunks.count == 1)
        #expect(chunks[0].status == .downloading)
    }
}
