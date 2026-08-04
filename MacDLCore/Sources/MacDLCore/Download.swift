import Foundation

public enum DownloadStatus: String, Codable {
    case active
    case paused
    case waiting
    case completed
    case stopped
    case error
}

public struct Download: Identifiable, Codable {
    public let id: UUID
    public var filename: String
    public let url: String
    public var totalSize: Int64
    public var downloadedSize: Int64
    public var downloadSpeed: Int64
    public var status: DownloadStatus
    public var addedAt: Date
    public var savePath: String?
    public var saveBookmark: Data?
    public var downloadLimit: Int?
    public var errorMessage: String?
    public var chunkSize: Int64 = 262144
    public var maxConcurrentChunks: Int = 8
    public var chunks: [Chunk] = []
    public var supportsResume: Bool?
    public var isPriorityDownload: Bool?
    public var pausedForPriority: Bool?

    public var progress: Double {
        totalSize > 0 ? min(Double(downloadedSize) / Double(totalSize), 1.0) : 0
    }

    public var estimatedTimeRemaining: TimeInterval? {
        guard downloadSpeed > 0, totalSize > downloadedSize else { return nil }
        return TimeInterval(totalSize - downloadedSize) / TimeInterval(downloadSpeed)
    }

    public init(id: UUID = UUID(), filename: String, url: String, totalSize: Int64 = 0, downloadedSize: Int64 = 0, downloadSpeed: Int64 = 0, status: DownloadStatus = .waiting, addedAt: Date = Date(), savePath: String? = nil, saveBookmark: Data? = nil, downloadLimit: Int? = nil, errorMessage: String? = nil, chunkSize: Int64 = 262144, maxConcurrentChunks: Int = 1, chunks: [Chunk] = [], supportsResume: Bool? = nil, isPriorityDownload: Bool? = nil, pausedForPriority: Bool? = nil) {
        self.id = id
        self.filename = filename
        self.url = url
        self.totalSize = totalSize
        self.downloadedSize = downloadedSize
        self.downloadSpeed = downloadSpeed
        self.status = status
        self.addedAt = addedAt
        self.savePath = savePath
        self.saveBookmark = saveBookmark
        self.downloadLimit = downloadLimit
        self.errorMessage = errorMessage
        self.chunkSize = chunkSize
        self.maxConcurrentChunks = maxConcurrentChunks
        self.chunks = chunks
        self.supportsResume = supportsResume
        self.isPriorityDownload = isPriorityDownload
        self.pausedForPriority = pausedForPriority
    }
}

public extension Download {
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

    func ensureChunks() -> [Chunk] {
        guard chunks.isEmpty else { return chunks }
        guard totalSize > 0 else { return [] }
        var result = buildChunks()
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
}
