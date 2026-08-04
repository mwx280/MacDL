import Foundation

/// Errors the engine surfaces to the app layer.
public enum DownloadError: Error, LocalizedError, Equatable {
    /// The task was cancelled by the user.
    case cancelled
    /// The destination file could not be opened for writing.
    case fileDeleted
    /// The requested byte range is not satisfiable by the server (416).
    case rangeNotSatisfiable
    /// The server file changed size mid-download; safe resume is impossible.
    case fileChanged
    /// An unexpected HTTP status was returned.
    case httpStatus(Int)
    /// A transport-level failure wrapped from `URLError` or similar.
    case network(Error)

    public static func == (lhs: DownloadError, rhs: DownloadError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled),
             (.fileDeleted, .fileDeleted),
             (.rangeNotSatisfiable, .rangeNotSatisfiable),
             (.fileChanged, .fileChanged):
            return true
        case (.httpStatus(let a), .httpStatus(let b)):
            return a == b
        case (.network, .network):
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
        case .httpStatus(let code):
            return "HTTP \(code)"
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }

    /// True when a retry is worth attempting (transient HTTP/network failures).
    public var isRetryable: Bool {
        switch self {
        case .cancelled, .fileDeleted, .rangeNotSatisfiable, .fileChanged: return false
        case .httpStatus(let code): return code == 429 || code >= 500
        case .network: return true
        }
    }
}
