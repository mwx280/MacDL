import Foundation
import MacDLCore

// Owns the priority-download state machine: promoting one download and
// auto-pausing the others, then restoring them when priority ends.
// Isolated from ContentViewModel so this flow is independently testable.
@MainActor
final class PriorityDownloadCoordinator {
    private let store: DownloadStore
    private let engine: DownloadEngineCoordinator
    private let resumeDownload: (UUID) -> Void

    private(set) var priorityDownloadID: UUID?
    private(set) var pausedForPriority: Set<UUID> = []

    init(store: DownloadStore, engine: DownloadEngineCoordinator, resumeDownload: @escaping (UUID) -> Void) {
        self.store = store
        self.engine = engine
        self.resumeDownload = resumeDownload
    }

    /// Rebuild priority state from the persisted store (app relaunch).
    func restoreFromStore() {
        pausedForPriority = Set(store.downloads.filter { $0.pausedForPriority == true }.map(\.id))
        priorityDownloadID = store.downloads.first { $0.isPriorityDownload == true }?.id
    }

    func setPriority(id: UUID) {
        guard let idx = store.index(of: id) else { return }
        guard [.active, .paused, .waiting].contains(store.downloads[idx].status) else { return }
        // Ensure the target is active
        if store.downloads[idx].status == .paused || store.downloads[idx].status == .waiting {
            resumeDownload(id)
        }

        // Replace: pause the old priority task and add it to the resume set
        if let old = priorityDownloadID, old != id {
            if let oi = store.index(of: old) {
                store.downloads[oi].isPriorityDownload = false
                if store.downloads[oi].status == .active {
                    engine.pause(old)
                    store.downloads[oi].status = .paused
                }
            }
            pausedForPriority.insert(old)
        }

        // Pause other active tasks (only those auto-paused for this priority)
        for i in store.downloads.indices where store.downloads[i].id != id && store.downloads[i].status == .active {
            engine.pause(store.downloads[i].id)
            store.downloads[i].status = .paused
            store.downloads[i].pausedForPriority = true
            pausedForPriority.insert(store.downloads[i].id)
        }

        priorityDownloadID = id
        if let ii = store.index(of: id) {
            store.downloads[ii].isPriorityDownload = true
        }
        store.save()
    }

    func cancelPriority(id: UUID) {
        guard id == priorityDownloadID else { return }
        end(excluding: nil)
    }

    /// Ends priority mode, resuming every task that was auto-paused unless it's
    /// the one being deleted (`skip`).
    func end(excluding skip: UUID? = nil) {
        priorityDownloadID = nil
        let toResume = pausedForPriority
        pausedForPriority.removeAll()
        for i in store.downloads.indices {
            store.downloads[i].isPriorityDownload = false
            if toResume.contains(store.downloads[i].id),
               store.downloads[i].id != skip,
               store.downloads[i].pausedForPriority == true {
                store.downloads[i].pausedForPriority = false
                resumeDownload(store.downloads[i].id)
            }
        }
        store.save()
    }
}
