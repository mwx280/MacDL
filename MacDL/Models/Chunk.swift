import Foundation

enum ChunkStatus: String, Codable {
    case pending
    case downloading
    case completed
    case failed
}

struct Chunk: Identifiable, Codable {
    let index: Int
    let startOffset: Int64
    let endOffset: Int64
    var downloadedSize: Int64
    var status: ChunkStatus

    var id: Int { index }
    var size: Int64 { endOffset - startOffset }
}
