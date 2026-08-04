import Foundation

// Renders the error text for a download row / notification.
//
// Download.errorKey is a catalog key persisted so the message re-localizes at
// display time (errorMessage alone goes stale when the app language changes).
// Legacy entries have no key and fall back to the persisted message.
enum DownloadErrorText {
    static func text(for download: Download) -> String? {
        if let key = download.errorKey {
            return LanguageManager.shared.localized(key)
        }
        return download.errorMessage
    }
}
