import Foundation

public enum ChunkStatus: String, Codable {
    case pending
    case downloading
    case completed
    case failed
}

public struct Chunk: Identifiable, Codable {
    public let index: Int
    public let startOffset: Int64
    public let endOffset: Int64
    public var downloadedSize: Int64
    public var status: ChunkStatus

    public var id: Int { index }
    public var size: Int64 { endOffset - startOffset }

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
