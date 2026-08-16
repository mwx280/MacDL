import Testing
import Foundation
@testable import MacDLCore

// Chunk-state reconstruction (compact resume state <-> chunk array) lives in
// the engine; these tests pin its semantics so the app model can rely on it.

private func chunk(_ index: Int, _ start: Int64, _ end: Int64, downloaded: Int64 = 0, status: ChunkStatus = .pending) -> Chunk {
    Chunk(index: index, startOffset: start, endOffset: end, downloadedSize: downloaded, status: status)
}

@Suite struct ChunkStateTests {

    // MARK: - completedRanges

    @Test func completedRangesMergeContiguousChunks() {
        let chunks = [
            chunk(0, 0, 256, downloaded: 256, status: .completed),
            chunk(1, 256, 512, downloaded: 256, status: .completed),
            chunk(2, 512, 768, downloaded: 100, status: .downloading),
        ]
        #expect(Chunk.completedRanges(of: chunks) == [CompletedRange(startOffset: 0, endOffset: 512)])
        #expect(Chunk.partialChunks(of: chunks) == [PartialChunk(index: 2, downloadedSize: 100)])
    }

    @Test func completedRangesKeepGapsSeparate() {
        let chunks = [
            chunk(0, 0, 256, downloaded: 256, status: .completed),
            chunk(2, 512, 768, downloaded: 256, status: .completed),
        ]
        #expect(Chunk.completedRanges(of: chunks) == [
            CompletedRange(startOffset: 0, endOffset: 256),
            CompletedRange(startOffset: 512, endOffset: 768),
        ])
    }

    @Test func completedRangesEmptyWhenNoneCompleted() {
        #expect(Chunk.completedRanges(of: [
            chunk(0, 0, 256, downloaded: 100, status: .downloading),
        ]).isEmpty)
    }

    @Test func partialChunksSkipCompletedAndEmpty() {
        let chunks = [
            chunk(0, 0, 256, downloaded: 256, status: .completed),
            chunk(1, 256, 512, downloaded: 0, status: .pending),
            chunk(2, 512, 768, downloaded: 90, status: .downloading),
        ]
        #expect(Chunk.partialChunks(of: chunks) == [PartialChunk(index: 2, downloadedSize: 90)])
    }

    // MARK: - ensureChunks

    @Test func ensureChunksMarksPartialProgress() {
        let chunks = Chunk.ensureChunks(totalSize: 1000, downloadedSize: 100, chunkSize: 256)
        #expect(chunks.count == 4)
        #expect(chunks[0].downloadedSize == 100)
        #expect(chunks[0].status == .pending)
        #expect(chunks[1].downloadedSize == 0)
        #expect(chunks[1].status == .pending)
    }

    @Test func ensureChunksMarksCompleted() {
        let chunks = Chunk.ensureChunks(totalSize: 1000, downloadedSize: 1000, chunkSize: 256)
        #expect(chunks.count == 4)
        #expect(chunks.allSatisfy { $0.status == .completed })
        #expect(chunks.allSatisfy { $0.downloadedSize == $0.size })
    }

    @Test func ensureChunksEmptyWhenTotalZero() {
        #expect(Chunk.ensureChunks(totalSize: 0, downloadedSize: 0, chunkSize: 256).isEmpty)
    }

    @Test func ensureChunksZeroProgressLeavesPending() {
        let chunks = Chunk.ensureChunks(totalSize: 1000, downloadedSize: 0, chunkSize: 256)
        #expect(chunks.allSatisfy { $0.status == .pending && $0.downloadedSize == 0 })
    }

    @Test func ensureChunksClampsOverDownloaded() {
        let chunks = Chunk.ensureChunks(totalSize: 1000, downloadedSize: 5000, chunkSize: 256)
        #expect(chunks.allSatisfy { $0.status == .completed && $0.downloadedSize == $0.size })
    }

    // MARK: - rebuildChunks

    @Test func rebuildFromContiguousRanges() {
        let chunks = Chunk.rebuildChunks(
            totalSize: 1000, chunkSize: 256,
            completedRanges: [CompletedRange(startOffset: 0, endOffset: 512)],
            partialChunks: [PartialChunk(index: 2, downloadedSize: 90)])
        #expect(chunks.count == 4)
        #expect(chunks[0].status == .completed)
        #expect(chunks[1].status == .completed)
        #expect(chunks[2].downloadedSize == 90)
        #expect(chunks[2].status != .completed)
        #expect(chunks[3].downloadedSize == 0)
        #expect(chunks[3].status == .pending)
    }

    @Test func rebuildFromGappedRanges() {
        let chunks = Chunk.rebuildChunks(
            totalSize: 1000, chunkSize: 256,
            completedRanges: [
                CompletedRange(startOffset: 0, endOffset: 256),
                CompletedRange(startOffset: 512, endOffset: 768),
            ],
            partialChunks: [])
        #expect(chunks[0].status == .completed)
        #expect(chunks[1].status != .completed)
        #expect(chunks[2].status == .completed)
        #expect(chunks[3].status != .completed)
    }

    @Test func rebuildEmptyWhenTotalZero() {
        #expect(Chunk.rebuildChunks(totalSize: 0, chunkSize: 256, completedRanges: [], partialChunks: []).isEmpty)
    }

    @Test func rebuildClampsPartialToChunkSize() {
        let chunks = Chunk.rebuildChunks(
            totalSize: 1000, chunkSize: 256,
            completedRanges: [],
            partialChunks: [PartialChunk(index: 2, downloadedSize: 100_000)])
        #expect(chunks[2].downloadedSize == chunks[2].size)
    }

    @Test func rebuildIgnoresOutOfRangePartial() {
        let chunks = Chunk.rebuildChunks(
            totalSize: 1000, chunkSize: 256,
            completedRanges: [],
            partialChunks: [PartialChunk(index: 99, downloadedSize: 100)])
        #expect(chunks.count == 4)
        #expect(chunks.allSatisfy { $0.downloadedSize == 0 })
    }

    @Test func rebuildPartialDoesNotTouchCompleted() {
        // A partial entry overlapping a completed range must not reset it.
        let chunks = Chunk.rebuildChunks(
            totalSize: 1000, chunkSize: 256,
            completedRanges: [CompletedRange(startOffset: 0, endOffset: 256)],
            partialChunks: [PartialChunk(index: 0, downloadedSize: 10)])
        #expect(chunks[0].status == .completed)
        #expect(chunks[0].downloadedSize == 256)
    }

    // MARK: - Round trip

    @Test func compactRoundTripPreservesState() {
        let original = [
            chunk(0, 0, 256, downloaded: 256, status: .completed),
            chunk(1, 256, 512, downloaded: 256, status: .completed),
            chunk(2, 512, 768, downloaded: 90, status: .downloading),
            chunk(3, 768, 1000, downloaded: 0, status: .pending),
        ]
        let ranges = Chunk.completedRanges(of: original)
        let partials = Chunk.partialChunks(of: original)
        let rebuilt = Chunk.rebuildChunks(totalSize: 1000, chunkSize: 256,
                                          completedRanges: ranges, partialChunks: partials)
        #expect(rebuilt.count == original.count)
        for (a, b) in zip(rebuilt, original) {
            #expect(a.startOffset == b.startOffset)
            #expect(a.endOffset == b.endOffset)
            if b.status == .completed {
                // Completed state round-trips exactly.
                #expect(a.status == .completed)
                #expect(a.downloadedSize == b.size)
            } else {
                // Transient downloading/pending collapses to pending on rebuild
                // (the compact format does not persist in-flight state).
                #expect(a.status == .pending)
                #expect(a.downloadedSize == b.downloadedSize)
            }
        }
    }
}
