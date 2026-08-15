import Foundation
import MacDLCore

public enum DownloadStatus: String, Codable, Sendable {
    case active
    case paused
    case waiting
    case completed
    case stopped
    case error
}

/// A merged contiguous run of fully-downloaded bytes. Persisted instead of the
/// full chunk array so a large file's resume state stays compact (a finished
/// 100 GB file is one range, not ~400k chunk entries).
public struct CompletedRange: Codable, Equatable, Sendable {
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
    public let index: Int
    public let downloadedSize: Int64

    public init(index: Int, downloadedSize: Int64) {
        self.index = index
        self.downloadedSize = downloadedSize
    }
}

public struct Download: Identifiable, Codable, Sendable {
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
    /// Catalog key of the error, so the message is re-localized at display time.
    /// `errorMessage` alone goes stale when the app language changes (it was
    /// persisted in whatever language was active when the error occurred).
    public var errorKey: String?
    public var errorMessage: String?
    public var chunkSize: Int64 = 262144
    public var maxConcurrentChunks: Int = 8
    /// Chunk progress, kept in sync with the engine during a session. Not
    /// persisted directly; on disk it is compacted into `completedRanges` and
    /// `partialChunks` and rebuilt here when the app restarts.
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

    /// Merged contiguous runs of fully-completed chunks, in offset order.
    public var completedRanges: [CompletedRange] {
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
    public var partialChunks: [PartialChunk] {
        chunks.compactMap { c in
            guard c.status != .completed, c.downloadedSize > 0 else { return nil }
            return PartialChunk(index: c.index, downloadedSize: c.downloadedSize)
        }
    }

    public init(id: UUID = UUID(), filename: String, url: String, totalSize: Int64 = 0, downloadedSize: Int64 = 0, downloadSpeed: Int64 = 0, status: DownloadStatus = .waiting, addedAt: Date = Date(), savePath: String? = nil, saveBookmark: Data? = nil, downloadLimit: Int? = nil, errorMessage: String? = nil, errorKey: String? = nil, chunkSize: Int64 = 262144, maxConcurrentChunks: Int = 8, chunks: [Chunk] = [], supportsResume: Bool? = nil, isPriorityDownload: Bool? = nil, pausedForPriority: Bool? = nil) {
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
        self.errorKey = errorKey
        self.chunkSize = chunkSize
        self.maxConcurrentChunks = maxConcurrentChunks
        self.chunks = chunks
        self.supportsResume = supportsResume
        self.isPriorityDownload = isPriorityDownload
        self.pausedForPriority = pausedForPriority
    }

    public func buildChunks() -> [Chunk] {
        guard totalSize > 0 else { return [] }
        return Chunk.chunks(totalSize: totalSize, chunkSize: chunkSize)
    }

    public func ensureChunks() -> [Chunk] {
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

    /// Rebuilds the chunk array from the compact resume state. Completed ranges
    /// mark whole chunks done; partial entries restore per-chunk resume offsets.
    public static func rebuildChunks(totalSize: Int64, chunkSize: Int64, completedRanges: [CompletedRange], partialChunks: [PartialChunk]) -> [Chunk] {
        guard totalSize > 0 else { return [] }
        var result = Chunk.chunks(totalSize: totalSize, chunkSize: chunkSize)
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

    // MARK: - Codable (compact persistence)

    private enum CodingKeys: String, CodingKey {
        case id, filename, url, totalSize, downloadedSize, downloadSpeed, status, addedAt
        case savePath, saveBookmark, downloadLimit, errorMessage, errorKey
        case chunkSize, maxConcurrentChunks, supportsResume, isPriorityDownload, pausedForPriority
        case completedRanges, partialChunks
        case chunks
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(filename, forKey: .filename)
        try c.encode(url, forKey: .url)
        try c.encode(totalSize, forKey: .totalSize)
        try c.encode(downloadedSize, forKey: .downloadedSize)
        try c.encode(downloadSpeed, forKey: .downloadSpeed)
        try c.encode(status, forKey: .status)
        try c.encode(addedAt, forKey: .addedAt)
        try c.encodeIfPresent(savePath, forKey: .savePath)
        try c.encodeIfPresent(saveBookmark, forKey: .saveBookmark)
        try c.encodeIfPresent(downloadLimit, forKey: .downloadLimit)
        try c.encodeIfPresent(errorMessage, forKey: .errorMessage)
        try c.encodeIfPresent(errorKey, forKey: .errorKey)
        try c.encode(chunkSize, forKey: .chunkSize)
        try c.encode(maxConcurrentChunks, forKey: .maxConcurrentChunks)
        try c.encodeIfPresent(supportsResume, forKey: .supportsResume)
        try c.encodeIfPresent(isPriorityDownload, forKey: .isPriorityDownload)
        try c.encodeIfPresent(pausedForPriority, forKey: .pausedForPriority)
        try c.encode(completedRanges, forKey: .completedRanges)
        try c.encode(partialChunks, forKey: .partialChunks)
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        filename = try c.decode(String.self, forKey: .filename)
        url = try c.decode(String.self, forKey: .url)
        totalSize = try c.decodeIfPresent(Int64.self, forKey: .totalSize) ?? 0
        downloadedSize = try c.decodeIfPresent(Int64.self, forKey: .downloadedSize) ?? 0
        downloadSpeed = try c.decodeIfPresent(Int64.self, forKey: .downloadSpeed) ?? 0
        status = try c.decodeIfPresent(DownloadStatus.self, forKey: .status) ?? .waiting
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        savePath = try c.decodeIfPresent(String.self, forKey: .savePath)
        saveBookmark = try c.decodeIfPresent(Data.self, forKey: .saveBookmark)
        downloadLimit = try c.decodeIfPresent(Int.self, forKey: .downloadLimit)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        errorKey = try c.decodeIfPresent(String.self, forKey: .errorKey)
        chunkSize = try c.decodeIfPresent(Int64.self, forKey: .chunkSize) ?? 262144
        maxConcurrentChunks = try c.decodeIfPresent(Int.self, forKey: .maxConcurrentChunks) ?? 8
        supportsResume = try c.decodeIfPresent(Bool.self, forKey: .supportsResume)
        isPriorityDownload = try c.decodeIfPresent(Bool.self, forKey: .isPriorityDownload)
        pausedForPriority = try c.decodeIfPresent(Bool.self, forKey: .pausedForPriority)

        // Legacy files stored the full chunk array; newer ones store the compact
        // resume state. A fresh/zero-progress download has neither, so it stays
        // chunk-less and the engine re-runs the range probe.
        if let legacy = try c.decodeIfPresent([Chunk].self, forKey: .chunks) {
            chunks = legacy
        } else {
            let ranges = try c.decodeIfPresent([CompletedRange].self, forKey: .completedRanges) ?? []
            let partials = try c.decodeIfPresent([PartialChunk].self, forKey: .partialChunks) ?? []
            if ranges.isEmpty && partials.isEmpty {
                chunks = []
            } else {
                chunks = Self.rebuildChunks(totalSize: totalSize, chunkSize: chunkSize, completedRanges: ranges, partialChunks: partials)
            }
        }
    }
}
