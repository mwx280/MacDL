import Foundation

enum DownloadStatus: String {
    case active
    case paused
    case waiting
    case completed
    case stopped
    case error

    var icon: String {
        switch self {
        case .active: "arrow.down.circle"
        case .paused: "pause.circle"
        case .waiting: "clock"
        case .completed: "checkmark.circle"
        case .stopped: "stop.circle"
        case .error: "exclamationmark.circle"
        }
    }
}

struct Download: Identifiable {
    let id: UUID
    let filename: String
    let url: String
    let totalSize: Int64
    var downloadedSize: Int64
    var downloadSpeed: Int64
    var uploadSpeed: Int64
    var status: DownloadStatus
    var addedAt: Date

    var progress: Double {
        totalSize > 0 ? min(Double(downloadedSize) / Double(totalSize), 1.0) : 0
    }
}
