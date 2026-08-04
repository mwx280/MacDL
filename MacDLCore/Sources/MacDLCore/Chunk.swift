import Foundation

/// Lifecycle state of a single chunk.
public enum ChunkStatus: String, Codable {
    case pending
    case downloading
    case completed
    case failed
}

/// A byte range of the file with its current progress. Codable so chunk state
/// survives restart and resumes exactly where it stopped.
public struct Chunk: Identifiable, Codable {
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
