import Foundation

/// Enforces a global cap on the total number of adaptive connections across all
/// running downloads, splitting the budget evenly (each download is still
/// capped at `perDownloadCap`). Prevents N downloads × max connections from
/// exhausting the network.
///
/// Pure state machine — the caller (`DownloadEngine`) registers and removes
/// downloads; each `ChunkManager` reads its current share via a closure. Mutable
/// state is guarded by `NSLock`, so the logic is fully unit-testable.
public final class ConnectionBudgetAllocator: @unchecked Sendable {
    private let lock = NSLock()
    private var participants: Set<UUID> = []
    /// Total connections available across all downloads.
    public let totalBudget: Int
    /// Hard cap on any single download.
    public let perDownloadCap: Int

    public init(totalBudget: Int, perDownloadCap: Int) {
        self.totalBudget = max(1, totalBudget)
        self.perDownloadCap = max(1, perDownloadCap)
    }

    /// Registers a running download. No-op when already registered.
    public func register(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        participants.insert(id)
    }

    /// Removes a finished or cancelled download.
    public func remove(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        participants.remove(id)
    }

    /// The even share for one download, capped at `perDownloadCap`. An
    /// unregistered id gets the full per-download cap so a manager used without
    /// a coordinator behaves as before.
    public func share(for id: UUID) -> Int {
        lock.lock(); defer { lock.unlock() }
        guard participants.contains(id) else { return perDownloadCap }
        return shareLocked()
    }

    /// Number of downloads currently sharing the budget.
    public var participantCount: Int {
        lock.lock(); defer { lock.unlock() }
        return participants.count
    }

    private func shareLocked() -> Int {
        let count = max(1, participants.count)
        return min(perDownloadCap, max(1, totalBudget / count))
    }
}
