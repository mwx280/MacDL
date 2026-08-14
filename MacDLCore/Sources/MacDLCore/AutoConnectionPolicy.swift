import Foundation

/// Pure, stateful decision logic for the "Auto" connection count — a
/// simplified IDM-style adaptive multi-connection controller.
///
/// Confined to one serial queue by the caller (`ChunkManager`): feed it one
/// smoothed speed sample per second via ``record(speed:)`` and ask it, at most
/// once per `evaluationInterval`, for the connection count to switch to via
/// ``evaluate(currentConnections:hasPending:)``. It probes one connection at a
/// time, keeps the probe only when throughput actually grew, remembers the best
/// count, and converges once the best speed is stable.
///
/// The policy has no timers or I/O, so its behaviour is fully unit-testable
/// from synthetic speed samples.
public struct AutoConnectionPolicy: Sendable {
    /// Lowest usable connection count.
    public let minConnections: Int
    /// Highest connection count the engine may use.
    public let maxConnections: Int
    /// A probe is kept only when steady speed grows by at least this fraction.
    public let gainThreshold: Double
    /// Minimum time between two connection changes.
    public let cooldown: TimeInterval
    /// How often ``evaluate`` may be called (the caller's timer cadence).
    public let evaluationInterval: TimeInterval
    /// Evaluations with no change before the policy declares itself converged.
    public let stableEvaluationsToConverge: Int

    public init(minConnections: Int = 1,
                maxConnections: Int = 8,
                gainThreshold: Double = 0.05,
                cooldown: TimeInterval = 3,
                evaluationInterval: TimeInterval = 3,
                stableEvaluationsToConverge: Int = 5) {
        self.minConnections = max(1, minConnections)
        self.maxConnections = max(self.minConnections, maxConnections)
        self.gainThreshold = max(0, gainThreshold)
        self.cooldown = max(0, cooldown)
        self.evaluationInterval = max(0.1, evaluationInterval)
        self.stableEvaluationsToConverge = max(1, stableEvaluationsToConverge)
    }

    /// Recommended starting connection count once the Range probe reveals the
    /// real file size and resume support. Non-resumable files can only stream
    /// in a single connection; tiny files do not benefit from parallelism.
    public static func initialConnectionCount(fileSize: Int64, supportsResume: Bool) -> Int {
        guard supportsResume else { return 1 }
        if fileSize < 1_048_576 { return 1 }              // < 1 MiB
        if fileSize < 16 * 1_048_576 { return 2 }         // < 16 MiB
        return 4                                          // ≥ 16 MiB, ramps up from here
    }

    // MARK: - State

    private var hasSmoothed = false
    private var smoothedSpeed: Int64 = 0
    private var bestSpeed: Int64 = 0
    private var bestConnections: Int = 1
    private var ceiling = Int.max
    private var isProbing = false
    private var probePrevSpeed: Int64 = 0
    private var probePrevConnections: Int = 1
    private var lastChangeAt: Date?
    private var stableCount = 0
    private var isConverged = false

    /// Resets all adaptive state (used when auto mode is re-entered).
    public mutating func reset() {
        hasSmoothed = false
        smoothedSpeed = 0
        bestSpeed = 0
        bestConnections = 1
        ceiling = Int.max
        isProbing = false
        probePrevSpeed = 0
        probePrevConnections = 1
        lastChangeAt = nil
        stableCount = 0
        isConverged = false
    }

    /// Smoothes a new aggregate-throughput sample (one per second). Uses an
    /// exponential moving average to damp short-lived speed spikes/dips.
    public mutating func record(speed: Int64) {
        let sample = max(0, speed)
        if !hasSmoothed {
            smoothedSpeed = sample
            hasSmoothed = true
        } else {
            smoothedSpeed = Int64((Double(smoothedSpeed) * 0.5) + (Double(sample) * 0.5))
        }
    }

    /// Called at most once per `evaluationInterval`. Returns the connection
    /// count to switch to, or `nil` to keep the current count.
    public mutating func evaluate(currentConnections: Int, hasPending: Bool, now: Date = Date()) -> Int? {
        guard !isConverged, hasSmoothed else { return nil }
        // Without queued chunks there is nothing new to parallelize; adding
        // connections can only waste a slot. (A file near completion drains its
        // queue, so this also stops late pointless ramping.)
        guard hasPending else { return nil }
        // Respect the cooldown between changes so decisions don't oscillate.
        if let last = lastChangeAt, now.timeIntervalSince(last) < cooldown { return nil }

        if smoothedSpeed > bestSpeed {
            bestSpeed = smoothedSpeed
            bestConnections = currentConnections
        }

        if isProbing {
            // Measure the probe: keep the added connection only if it paid off.
            lastChangeAt = now
            stableCount = 0
            if Double(smoothedSpeed) >= Double(probePrevSpeed) * (1 + gainThreshold) {
                isProbing = false
                return nil
            } else {
                // Diminishing returns — revert and remember this level as the ceiling.
                isProbing = false
                ceiling = probePrevConnections
                return probePrevConnections
            }
        }

        // Revert to the best count if the current one is doing clearly worse.
        if bestSpeed > 0, Double(smoothedSpeed) < Double(bestSpeed) * 0.8, currentConnections > bestConnections {
            lastChangeAt = now
            stableCount = 0
            return bestConnections
        }

        // Otherwise probe one connection higher.
        guard smoothedSpeed > 0, currentConnections < maxConnections, currentConnections < ceiling else {
            stableCount += 1
            if stableCount >= stableEvaluationsToConverge {
                isConverged = true
            }
            return nil
        }
        probePrevSpeed = smoothedSpeed
        probePrevConnections = currentConnections
        isProbing = true
        lastChangeAt = now
        stableCount = 0
        return currentConnections + 1
    }
}
