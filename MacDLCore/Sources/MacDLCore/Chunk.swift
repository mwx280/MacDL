import Foundation

/// Lifecycle state of a single chunk.
public enum ChunkStatus: String, Codable, Sendable {
    case pending
    case downloading
    case completed
    case failed
}

/// A byte range of the file with its current progress. Codable so chunk state
/// survives restart and resumes exactly where it stopped.
public struct Chunk: Identifiable, Codable, Sendable {
    /// Position in the chunk array.
    public let index: Int
    /// First byte offset of the range, inclusive.
    public let startOffset: Int64
    /// One past the last byte of the range, exclusive.
    public let endOffset: Int64
    /// Bytes written so far.
    public var downloadedSize: Int64
    /// Current lifecycle state.
    public var status: ChunkStatus

    public var id: Int { index }
    /// Size of the range in bytes.
    public var size: Int64 { endOffset - startOffset }

    /// Creates a chunk.
    public init(index: Int, startOffset: Int64, endOffset: Int64, downloadedSize: Int64, status: ChunkStatus) {
        self.index = index
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.downloadedSize = downloadedSize
        self.status = status
    }

    /// Canonical fixed-size splitter used by both the engine and the model.
    public static func chunks(totalSize: Int64, chunkSize: Int64) -> [Chunk] {
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

/// A merged contiguous run of fully-downloaded bytes. The compact resume state
/// persists these instead of the full chunk array, so a large file's state
/// stays small (a finished 100 GB file is one range, not ~400k chunk entries).
public struct CompletedRange: Codable, Equatable, Sendable {
    /// First byte offset of the run, inclusive.
    public let startOffset: Int64
    /// One past the last byte of the run, exclusive.
    public let endOffset: Int64

    public init(startOffset: Int64, endOffset: Int64) {
        self.startOffset = startOffset
        self.endOffset = endOffset
    }
}

/// A not-yet-completed chunk that already has bytes on disk. Pending chunks
/// (0 bytes) are not persisted.
public struct PartialChunk: Codable, Equatable, Sendable {
    /// Position in the chunk array.
    public let index: Int
    /// Bytes written so far.
    public let downloadedSize: Int64

    public init(index: Int, downloadedSize: Int64) {
        self.index = index
        self.downloadedSize = downloadedSize
    }
}

// Chunk-state reconstruction lives in the engine so chunk semantics have a
// single source of truth; the app model only stores and renders this state.

public extension Chunk {
    /// Merged contiguous runs of fully-completed chunks, in offset order.
    static func completedRanges(of chunks: [Chunk]) -> [CompletedRange] {
        var result: [CompletedRange] = []
        var start: Int64?
        var end: Int64 = 0
        for c in chunks where c.status == .completed {
            if start == nil {
                start = c.startOffset
            }
            if c.startOffset == end {
                end = c.endOffset
            } else {
                if let s = start {
                    result.append(CompletedRange(startOffset: s, endOffset: end))
                }
                start = c.startOffset
                end = c.endOffset
            }
        }
        if let s = start {
            result.append(CompletedRange(startOffset: s, endOffset: end))
        }
        return result
    }

    /// Non-completed chunks that already hold bytes (resume points).
    static func partialChunks(of chunks: [Chunk]) -> [PartialChunk] {
        chunks.compactMap { c in
            guard c.status != .completed, c.downloadedSize > 0 else { return nil }
            return PartialChunk(index: c.index, downloadedSize: c.downloadedSize)
        }
    }

    /// Splits a file into chunks and marks progress from a single downloaded
    /// byte count (used when the in-memory chunk array was lost, e.g. resume
    /// after a restart without persisted per-chunk state).
    static func ensureChunks(totalSize: Int64, downloadedSize: Int64, chunkSize: Int64) -> [Chunk] {
        guard totalSize > 0 else { return [] }
        var result = chunks(totalSize: totalSize, chunkSize: chunkSize)
        var remaining = downloadedSize
        for i in result.indices {
            let take = min(remaining, result[i].size)
            if take >= result[i].size {
                result[i].status = .completed
                result[i].downloadedSize = result[i].size
            } else if take > 0 {
                result[i].status = .pending
                result[i].downloadedSize = take
            }
            remaining -= take
            if remaining <= 0 { break }
        }
        return result
    }

    /// Rebuilds the chunk array from the compact resume state. Completed ranges
    /// mark whole chunks done; partial entries restore per-chunk resume offsets.
    static func rebuildChunks(totalSize: Int64, chunkSize: Int64, completedRanges: [CompletedRange], partialChunks: [PartialChunk]) -> [Chunk] {
        guard totalSize > 0 else { return [] }
        var result = chunks(totalSize: totalSize, chunkSize: chunkSize)
        // Both chunks and completedRanges are ordered by offset, so a single
        // merge pass marks completed chunks in O(n + m) instead of O(n * m).
        var r = 0
        for i in result.indices {
            let c = result[i]
            while r < completedRanges.count, completedRanges[r].endOffset <= c.startOffset {
                r += 1
            }
            if r < completedRanges.count,
               c.startOffset >= completedRanges[r].startOffset,
               c.endOffset <= completedRanges[r].endOffset {
                result[i].status = .completed
                result[i].downloadedSize = c.size
            }
        }
        for p in partialChunks where p.index < result.count {
            let c = result[p.index]
            if c.status != .completed {
                result[p.index].downloadedSize = min(p.downloadedSize, c.size)
            }
        }
        return result
    }
}
