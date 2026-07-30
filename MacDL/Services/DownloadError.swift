import Foundation

enum DownloadError: Error, LocalizedError {
    case cancelled
    case fileDeleted
    var errorDescription: String? {
        switch self {
        case .cancelled: return "下载已取消"
        case .fileDeleted: return "下载文件已被删除"
        }
    }
}
