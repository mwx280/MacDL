import Foundation
import Observation
import MacDLCore

// Owns the download list and its persistence. ContentViewModel keeps the
// @Observable surface that SwiftUI binds to; this store is the single source
// of truth for the model so engine coordination and UI actions share it.
@Observable
final class DownloadStore {
    var downloads: [Download]

    private let persistence: DownloadPersistence

    init(persistence: DownloadPersistence) {
        self.persistence = persistence
        self.downloads = persistence.load()
    }

    func save(_ caller: String = "downloadStore") {
        persistence.save(downloads, caller: caller)
    }

    func index(of id: UUID) -> Int? {
        downloads.firstIndex { $0.id == id }
    }

    func update(_ id: UUID, _ mutate: (inout Download) -> Void) {
        guard let idx = index(of: id) else { return }
        mutate(&downloads[idx])
    }

    func append(_ download: Download) {
        downloads.append(download)
    }

    func remove(_ id: UUID) {
        downloads.removeAll { $0.id == id }
    }

    /// Rebuilds chunk state from persisted progress (resume support).
    func ensureChunks(for id: UUID) {
        update(id) { d in
            let built = d.ensureChunks()
            d.chunks = built
            d.downloadedSize = built.reduce(0) { $0 + $1.downloadedSize }
            d.totalSize = built.last?.endOffset ?? 0
        }
    }
}
