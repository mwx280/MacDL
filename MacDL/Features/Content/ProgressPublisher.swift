import AppKit
import Foundation
import MacDLCore

// Publishes, updates and unpublishes Finder download progress badges (NSProgress).
// Main-actor isolated: published/updated from the main thread; the cancellation
// handler dispatches back to main before touching state, so no lock is needed.
@MainActor
final class ProgressPublisher {
    private var progressMap: [UUID: Progress] = [:]
    private var onCancel: (UUID) -> Void = { _ in }

    init() {}

    func setCancelHandler(_ handler: @escaping (UUID) -> Void) {
        onCancel = handler
    }

    func isPublished(for id: UUID) -> Bool {
        progressMap[id] != nil
    }

    func publish(for download: Download, fileURL: URL) {
        let downloadID = download.id
        let p = Progress(totalUnitCount: max(download.totalSize, 1))
        p.kind = .file
        p.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        p.setUserInfoObject(fileURL, forKey: .fileURLKey)
        p.completedUnitCount = download.downloadedSize
        p.cancellationHandler = { [weak self] in
            DispatchQueue.main.async {
                self?.unpublish(for: downloadID)
                self?.onCancel(downloadID)
            }
        }
        p.publish()
        progressMap[download.id] = p
    }

    func update(for id: UUID, download: Download) {
        guard let p = progressMap[id] else { return }
        p.totalUnitCount = max(download.totalSize, 1)
        p.completedUnitCount = download.downloadedSize
        p.isCancellable = download.status == .active
    }

    func unpublish(for id: UUID) {
        let p = progressMap.removeValue(forKey: id)
        p?.unpublish()
    }

    func unpublishAll() {
        let all = progressMap.values
        progressMap.removeAll()
        for p in all { p.unpublish() }
    }
}
