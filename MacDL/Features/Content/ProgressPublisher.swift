import AppKit
import Foundation
import MacDLCore

// Publishes, updates and unpublishes Finder download progress badges (NSProgress).
final class ProgressPublisher {
    private var progressMap: [UUID: Progress] = [:]
    private let lock = NSLock()
    private var onCancel: (UUID) -> Void = { _ in }

    init() {}

    func setCancelHandler(_ handler: @escaping (UUID) -> Void) {
        lock.lock()
        onCancel = handler
        lock.unlock()
    }

    func isPublished(for id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return progressMap[id] != nil
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
        lock.lock()
        progressMap[download.id] = p
        lock.unlock()
    }

    func update(for id: UUID, download: Download) {
        lock.lock()
        guard let p = progressMap[id] else { lock.unlock(); return }
        p.totalUnitCount = max(download.totalSize, 1)
        p.completedUnitCount = download.downloadedSize
        p.isCancellable = download.status == .active
        lock.unlock()
    }

    func unpublish(for id: UUID) {
        lock.lock()
        let p = progressMap.removeValue(forKey: id)
        lock.unlock()
        p?.unpublish()
    }

    func unpublishAll() {
        lock.lock()
        let all = progressMap.values
        progressMap.removeAll()
        lock.unlock()
        for p in all { p.unpublish() }
    }
}
