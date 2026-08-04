import Foundation
import MacDLCore

// Manages security-scoped access to user-picked download folders under the sandbox.
// The default Downloads folder is covered by the downloads entitlement, so only
// custom folders need a bookmark resolved this way.
final class SandboxAccess {
    static let shared = SandboxAccess()

    private var active: [UUID: URL] = [:]
    // Shared singleton: beginAccess/endAccess can arrive from the test host's
    // parallel suites (and any background path), so serialize the dictionary.
    private let lock = NSLock()

    // Returns true when the app is allowed to write into the download's folder.
    // Every true result must be paired with endAccess once the download is done.
    func beginAccess(for download: Download) -> Bool {
        guard let savePath = download.savePath else { return true }
        // Default Downloads: granted directly by the entitlement.
        if savePath == AppConfig.defaultDownloadDir { return true }
        guard let bookmark = download.saveBookmark else { return false }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return false }
        guard url.startAccessingSecurityScopedResource() else { return false }
        lock.lock()
        active[download.id] = url
        lock.unlock()
        return true
    }

    func endAccess(for id: UUID) {
        lock.lock()
        let url = active.removeValue(forKey: id)
        lock.unlock()
        url?.stopAccessingSecurityScopedResource()
    }

    func endAllAccess() {
        lock.lock()
        let all = Array(active.values)
        active.removeAll()
        lock.unlock()
        for url in all { url.stopAccessingSecurityScopedResource() }
    }
}
