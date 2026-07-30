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

    var progress: Double {
        totalSize > 0 ? min(Double(downloadedSize) / Double(totalSize), 1.0) : 0
    }

    init(id: UUID = UUID(), filename: String, url: String, totalSize: Int64 = 0, downloadedSize: Int64 = 0, downloadSpeed: Int64 = 0, status: DownloadStatus = .waiting, addedAt: Date = Date(), savePath: String? = nil, downloadLimit: Int? = nil, errorMessage: String? = nil) {
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
    }
}
