import Foundation

enum DownloadError: Error, LocalizedError {
    case cancelled
    case fileDeleted
    case rangeNotSatisfiable
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return LanguageManager.shared.localized("Cancelled")
        case .fileDeleted:
            return LanguageManager.shared.localized("Download file has been deleted")
        case .rangeNotSatisfiable:
            return LanguageManager.shared.localized("Server does not support this download range")
        case .network(let error):
            return String(
                format: LanguageManager.shared.localized("Network error: %@"),
                error.localizedDescription
            )
        }
    }

    var isRetryable: Bool {
        switch self {
        case .cancelled, .fileDeleted, .rangeNotSatisfiable: return false
        case .network: return true
        }
    }
}
