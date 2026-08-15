import Foundation

/// One remote source (the primary URL or a mirror) for a download, carrying a
/// lightweight cooldown state so a failing source is sidelined and its chunks
/// fail over to healthier sources.
///
/// Pure value logic; the cooldown thresholds live in ``EngineConstants`` and the
/// caller mutates this on a serial queue.
public struct Source: Equatable, Sendable {
    /// The source's remote URL.
    public let url: URL
    /// Consecutive retryable failures seen so far.
    public var consecutiveFailures: Int
    /// When set, the source is sidelined until this time.
    public var cooldownUntil: Date?

    public init(url: URL, consecutiveFailures: Int = 0, cooldownUntil: Date? = nil) {
        self.url = url
        self.consecutiveFailures = consecutiveFailures
        self.cooldownUntil = cooldownUntil
    }

    /// Whether the source may be used for new requests right now.
    public func isAvailable(at now: Date = Date()) -> Bool {
        guard let until = cooldownUntil else { return true }
        return now >= until
    }

    /// Records a retryable failure. Once the failure streak reaches
    /// `threshold`, the source is put into cooldown for `cooldown` seconds.
    public mutating func recordFailure(now: Date = Date(), threshold: Int, cooldown: TimeInterval) {
        consecutiveFailures += 1
        if consecutiveFailures >= threshold {
            consecutiveFailures = 0
            cooldownUntil = now.addingTimeInterval(cooldown)
        }
    }

    /// Records a success, clearing any failure streak and cooldown.
    public mutating func recordSuccess() {
        consecutiveFailures = 0
        cooldownUntil = nil
    }
}
