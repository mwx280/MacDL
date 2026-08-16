import Foundation
import Network

/// System-level network reachability. The engine uses it to hold downloads
/// while the local link is down — instead of burning retries against a dead
/// network — and to kick them back to life when the link returns.
///
/// Tests drive `simulate(_:)` instead of touching the real network.
/// @unchecked Sendable: mutable state is guarded by `NSLock`.
public final class NetworkReachability: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.xiaowu.networkreachability")
    private let lock = NSLock()
    private var satisfiedOverride: Bool?
    private var changeHandler: ((Bool) -> Void)?

    public init() {}

    /// Whether the network path is currently satisfied (a usable link).
    public var isSatisfied: Bool {
        lock.lock()
        defer { lock.unlock() }
        if let o = satisfiedOverride { return o }
        return monitor.currentPath.status == .satisfied
    }

    /// Starts monitoring. `handler` fires with the new reachability each time
    /// the path changes (and once initially), on an internal queue.
    public func start(handler: @escaping (Bool) -> Void) {
        lock.lock()
        changeHandler = handler
        lock.unlock()
        monitor.pathUpdateHandler = { [weak self] path in
            self?.notify(path.status == .satisfied)
        }
        monitor.start(queue: queue)
    }

    /// Stops monitoring.
    public func stop() {
        monitor.cancel()
    }

    /// Test hook: forces the reported reachability and fires the change handler,
    /// simulating a link drop/restore without real networking.
    public func simulate(_ satisfied: Bool) {
        lock.lock()
        satisfiedOverride = satisfied
        let handler = changeHandler
        lock.unlock()
        handler?(satisfied)
    }

    private func notify(_ satisfied: Bool) {
        lock.lock()
        let handler = changeHandler
        lock.unlock()
        handler?(satisfied)
    }
}
