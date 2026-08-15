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
    /// EWMA of observed throughput (bytes/second) for this source, used as the
    /// scheduling weight so faster sources serve more chunks.
    public var avgThroughput: Int64

    public init(url: URL, consecutiveFailures: Int = 0, cooldownUntil: Date? = nil, avgThroughput: Int64 = 0) {
        self.url = url
        self.consecutiveFailures = consecutiveFailures
        self.cooldownUntil = cooldownUntil
        self.avgThroughput = avgThroughput
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

    /// Folds a per-chunk throughput sample into the source's EWMA.
    public mutating func recordThroughput(_ bytesPerSecond: Int64) {
        let sample = max(0, bytesPerSecond)
        if avgThroughput == 0 {
            avgThroughput = sample
        } else {
            avgThroughput = Int64((Double(avgThroughput) * 0.7) + (Double(sample) * 0.3))
        }
    }
}
