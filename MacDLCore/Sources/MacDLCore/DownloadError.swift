import Foundation

public enum DownloadError: Error, LocalizedError, Equatable {
    case cancelled
    case fileDeleted
    case rangeNotSatisfiable
    case fileChanged
    case network(Error)

    public static func == (lhs: DownloadError, rhs: DownloadError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled),
             (.fileDeleted, .fileDeleted),
             (.rangeNotSatisfiable, .rangeNotSatisfiable),
             (.fileChanged, .fileChanged),
             (.network, .network):
            return true
        default:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Cancelled"
        case .fileDeleted:
            return "Download file has been deleted"
        case .rangeNotSatisfiable:
            return "Server does not support this download range"
        case .fileChanged:
            return "File changed on server, resume not possible"
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .cancelled, .fileDeleted, .rangeNotSatisfiable, .fileChanged: return false
        case .network: return true
        }
    }
}
