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
}
