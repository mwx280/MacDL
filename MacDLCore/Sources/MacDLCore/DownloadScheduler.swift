import Foundation

/// Cross-download scheduling: a global concurrency cap with a FIFO waiting
/// queue. Decides which download runs and which waits, and which queued
/// download starts when a slot frees.
///
/// Pure state machine — the caller (``DownloadEngine``) performs the actual
/// start/stop of managers. The scheduler only tracks order and capacity, so
/// its logic is fully unit-testable without any I/O.
/// @unchecked Sendable: mutable state is guarded by `NSLock`.
public final class DownloadScheduler: @unchecked Sendable {
    private let lock = NSLock()
    private var running: Set<UUID> = []
    private var waiting: [UUID] = []
    private var capacity: Int

    /// Creates a scheduler with a concurrency cap (minimum 1).
    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    /// Changes the concurrency cap. Returns ids that should start now because a
    /// grown cap pulled waiting downloads into the running set.
    public func setCapacity(_ newCapacity: Int) -> [UUID] {
        lock.lock()
        defer { lock.unlock() }
        capacity = max(1, newCapacity)
        return promoteWhileSpace()
    }

    /// Registers a download. It runs immediately when under the cap, otherwise
    /// it is queued FIFO. Returns `true` when it should start now.
    public func schedule(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if running.contains(id) || waiting.contains(id) {
            return running.contains(id)
        }
        if running.count < capacity {
            running.insert(id)
            return true
        }
        waiting.append(id)
        return false
    }

    /// Registers a download into the waiting queue without starting it (used to
    /// restore persisted waiting downloads on launch). No-op if already known.
    public func enqueue(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard !running.contains(id), !waiting.contains(id) else { return }
        waiting.append(id)
    }

    /// Called when a running download finishes. Removes it from the running set
    /// and returns the queued ids promoted into the freed slot(s).
    public func finished(_ id: UUID) -> [UUID] {
        lock.lock()
        defer { lock.unlock() }
        running.remove(id)
        waiting.removeAll { $0 == id }
        return promoteWhileSpace()
    }

    /// Removes a download from either the running or waiting set (delete /
    /// cancel). Returns ids promoted into any freed slot.
    public func remove(_ id: UUID) -> [UUID] {
        lock.lock()
        defer { lock.unlock() }
        let wasRunning = running.remove(id) != nil
        waiting.removeAll { $0 == id }
        guard wasRunning else { return [] }
        return promoteWhileSpace()
    }

    /// Whether `id` is currently running.
    public func isRunning(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return running.contains(id)
    }

    /// Whether `id` is currently waiting in the queue.
    public func isWaiting(_ id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return waiting.contains(id)
    }

    /// Number of currently running downloads.
    public var activeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return running.count
    }

    /// Number of queued downloads.
    public var waitingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return waiting.count
    }

    /// Pops queued ids into the running set while capacity allows, in FIFO
    /// order. Call with the lock held.
    private func promoteWhileSpace() -> [UUID] {
        var promoted: [UUID] = []
        while running.count < capacity, let next = waiting.first {
            waiting.removeFirst()
            running.insert(next)
            promoted.append(next)
        }
        return promoted
    }
}
