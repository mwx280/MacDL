import Testing
import Foundation
import MacDLCore
@testable import MacDL

@MainActor
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

    // MARK: - Compact persistence

    @Test func completedRangesMergeContiguousChunks() {
        let chunks = [
            Chunk(index: 0, startOffset: 0, endOffset: 256, downloadedSize: 256, status: .completed),
            Chunk(index: 1, startOffset: 256, endOffset: 512, downloadedSize: 256, status: .completed),
            Chunk(index: 2, startOffset: 512, endOffset: 768, downloadedSize: 100, status: .downloading),
        ]
        let d = makeDownload(totalSize: 1000, chunks: chunks)
        #expect(d.completedRanges == [CompletedRange(startOffset: 0, endOffset: 512)])
        #expect(d.partialChunks == [PartialChunk(index: 2, downloadedSize: 100)])
    }

    @Test func completedRangesKeepGapsSeparate() {
        let chunks = [
            Chunk(index: 0, startOffset: 0, endOffset: 256, downloadedSize: 256, status: .completed),
            Chunk(index: 2, startOffset: 512, endOffset: 768, downloadedSize: 256, status: .completed),
        ]
        let d = makeDownload(totalSize: 1000, chunks: chunks)
        #expect(d.completedRanges == [
            CompletedRange(startOffset: 0, endOffset: 256),
            CompletedRange(startOffset: 512, endOffset: 768),
        ])
    }

    @Test func codableRoundTripsChunkStateLosslessly() throws {
        let chunks = [
            Chunk(index: 0, startOffset: 0, endOffset: 256, downloadedSize: 256, status: .completed),
            Chunk(index: 1, startOffset: 256, endOffset: 512, downloadedSize: 256, status: .completed),
            Chunk(index: 2, startOffset: 512, endOffset: 768, downloadedSize: 90, status: .downloading),
            Chunk(index: 3, startOffset: 768, endOffset: 1000, downloadedSize: 0, status: .pending),
        ]
        let d = makeDownload(totalSize: 1000, downloadedSize: 602, chunks: chunks)
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(Download.self, from: data)

        // Decoded JSON must not carry the full chunk array.
        let json = String(data: data, encoding: .utf8) ?? ""
        #expect(!json.contains("\"chunks\""))

        #expect(decoded.chunks.count == 4)
        #expect(decoded.chunks[0].status == .completed)
        #expect(decoded.chunks[0].downloadedSize == 256)
        #expect(decoded.chunks[1].status == .completed)
        #expect(decoded.chunks[2].downloadedSize == 90)
        #expect(decoded.chunks[2].status != .completed)
        #expect(decoded.chunks[3].downloadedSize == 0)
        #expect(decoded.totalSize == 1000)
        #expect(decoded.downloadedSize == 602)
    }

    @Test func codableRoundTripsEmptyChunks() throws {
        let d = makeDownload(totalSize: 1000)
        let decoded = try JSONDecoder().decode(Download.self, from: try JSONEncoder().encode(d))
        #expect(decoded.chunks.isEmpty)
    }

    @Test func legacyChunksStillDecode() throws {
        let json = """
        {"id": "\(UUID().uuidString)", "filename": "a.bin", "url": "https://e.com/a.bin", "totalSize": 1000, "downloadedSize": 256, "downloadSpeed": 0, "status": "active", "addedAt": 0, "chunkSize": 256, "maxConcurrentChunks": 4, "chunks": [{"index": 0, "startOffset": 0, "endOffset": 256, "downloadedSize": 256, "status": "completed"}]}
        """
        let d = try JSONDecoder().decode(Download.self, from: Data(json.utf8))
        #expect(d.chunks.count == 1)
        #expect(d.chunks[0].status == .completed)
    }

    @Test func compactStateRebuildsChunksOnDecode() throws {
        let json = """
        {"id": "\(UUID().uuidString)", "filename": "a.bin", "url": "https://e.com/a.bin", "totalSize": 1000, "downloadedSize": 602, "downloadSpeed": 0, "status": "active", "addedAt": 0, "chunkSize": 256, "maxConcurrentChunks": 4, "completedRanges": [{"startOffset": 0, "endOffset": 512}], "partialChunks": [{"index": 2, "downloadedSize": 90}]}
        """
        let d = try JSONDecoder().decode(Download.self, from: Data(json.utf8))
        #expect(d.chunks.count == 4)
        #expect(d.chunks[0].status == .completed)
        #expect(d.chunks[1].status == .completed)
        #expect(d.chunks[2].downloadedSize == 90)
        #expect(d.chunks[2].status != .completed)
        #expect(d.chunks[3].downloadedSize == 0)
    }

    @Test func emptyCompactStateLeavesChunksEmpty() throws {
        let json = """
        {"id": "\(UUID().uuidString)", "filename": "a.bin", "url": "https://e.com/a.bin", "totalSize": 1000, "downloadedSize": 0, "downloadSpeed": 0, "status": "waiting", "addedAt": 0, "chunkSize": 256, "maxConcurrentChunks": 4}
        """
        let d = try JSONDecoder().decode(Download.self, from: Data(json.utf8))
        #expect(d.chunks.isEmpty)
    }
}
