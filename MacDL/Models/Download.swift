import Foundation

enum DownloadStatus: String, Codable {
    case active
    case paused
    case waiting
    case completed
    case stopped
    case error
}

struct Download: Identifiable, Codable {
    let id: UUID
    var filename: String
    let url: String
    var totalSize: Int64
    var downloadedSize: Int64
    var downloadSpeed: Int64
    var status: DownloadStatus
    var addedAt: Date
    var savePath: String?
    var downloadLimit: Int?
    var errorMessage: String?
    var chunkSize: Int64 = 262144
    var maxConcurrentChunks: Int = 1
    var chunks: [Chunk] = []

    var progress: Double {
        totalSize > 0 ? min(Double(downloadedSize) / Double(totalSize), 1.0) : 0
    }

    init(id: UUID = UUID(), filename: String, url: String, totalSize: Int64 = 0, downloadedSize: Int64 = 0, downloadSpeed: Int64 = 0, status: DownloadStatus = .waiting, addedAt: Date = Date(), savePath: String? = nil, downloadLimit: Int? = nil, errorMessage: String? = nil, chunkSize: Int64 = 262144, maxConcurrentChunks: Int = 1, chunks: [Chunk] = []) {
        self.id = id
        self.filename = filename
        self.url = url
        self.totalSize = totalSize
        self.downloadedSize = downloadedSize
        self.downloadSpeed = downloadSpeed
        self.status = status
        self.addedAt = addedAt
        self.savePath = savePath
        self.downloadLimit = downloadLimit
        self.errorMessage = errorMessage
        self.chunkSize = chunkSize
        self.maxConcurrentChunks = maxConcurrentChunks
        self.chunks = chunks
    }
}

extension Download {
    func buildChunks() -> [Chunk] {
        guard totalSize > 0 else { return [] }
        var result: [Chunk] = []
        let chunkSize = max(Int64(1), chunkSize)
        var offset: Int64 = 0
        var index = 0
        while offset < totalSize {
            let end = min(offset + chunkSize, totalSize)
            result.append(Chunk(index: index, startOffset: offset, endOffset: end, downloadedSize: 0, status: .pending))
            offset = end
            index += 1
        }
        return result
    }

    func activeChunkCount(in chunks: [Chunk]) -> Int {
        chunks.filter { $0.status == .downloading }.count
    }

    func calcDownloadedSize(from chunks: [Chunk]) -> Int64 {
        chunks.filter { $0.status == .completed }.reduce(0) { $0 + $1.size } +
        chunks.filter { $0.status == .downloading }.reduce(0) { $0 + $1.downloadedSize }
    }
}
