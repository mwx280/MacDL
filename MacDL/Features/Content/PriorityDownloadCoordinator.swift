import Foundation
import MacDLCore

// Owns the priority-download state that lives outside the engine: the persisted
// flags (`isPriorityDownload`, `pausedForPriority`) and the status updates that
// flow from the engine's scheduling callbacks. The engine decides WHICH
// downloads get paused/resumed for priority (setPriorityDownload /
// endPriority); this coordinator keeps the store and UI in sync.
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
        // The engine drives the pause/restore; reflect it in the store.
        engine.onPriorityPaused = { [weak self] id in
            self?.markPausedForPriority(id)
        }
        engine.onPriorityResumed = { [weak self] id in
            self?.markResumedFromPriority(id)
        }
    }

    /// Rebuild priority state from the persisted store (app relaunch).
    func restoreFromStore() {
        pausedForPriority = Set(store.downloads.filter { $0.pausedForPriority == true }.map(\.id))
        priorityDownloadID = store.downloads.first { $0.isPriorityDownload == true }?.id
        // The engine was restarted and forgets which downloads were paused for
        // priority; re-register them so endPriority can restore them.
        engine.registerPriorityPaused(pausedForPriority)
    }

    func setPriority(id: UUID) {
        guard let idx = store.index(of: id) else { return }
        guard [.active, .paused, .waiting].contains(store.downloads[idx].status) else { return }

        // Replacing an old priority: drop its flag; the engine pauses it along
        // with the other running downloads.
        if let old = priorityDownloadID, old != id {
            if let oi = store.index(of: old) {
                store.downloads[oi].isPriorityDownload = false
            }
        }

        priorityDownloadID = id
        if let ii = store.index(of: id) {
            store.downloads[ii].isPriorityDownload = true
            // The engine starts it if it was queued/paused; either way it runs.
            store.downloads[ii].status = .active
        }
        store.save()
        engine.setPriorityDownload(id: id)
    }

    func cancelPriority(id: UUID) {
        guard id == priorityDownloadID else { return }
        end(excluding: nil)
    }

    /// Ends priority mode, resuming every task auto-paused for priority unless
    /// it's the one being deleted (`skip`).
    func end(excluding skip: UUID? = nil) {
        priorityDownloadID = nil
        for i in store.downloads.indices {
            store.downloads[i].isPriorityDownload = false
        }
        store.save()
        engine.endPriority(excluding: skip)
    }

    private func markPausedForPriority(_ id: UUID) {
        guard let idx = store.index(of: id) else { return }
        store.downloads[idx].status = .paused
        store.downloads[idx].pausedForPriority = true
        pausedForPriority.insert(id)
        store.save()
    }

    private func markResumedFromPriority(_ id: UUID) {
        guard let idx = store.index(of: id) else { return }
        store.downloads[idx].pausedForPriority = false
        pausedForPriority.remove(id)
        store.save()
        resumeDownload(id)
    }
}
