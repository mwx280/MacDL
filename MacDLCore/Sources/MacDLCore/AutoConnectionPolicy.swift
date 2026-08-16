import Foundation

/// Pure, stateful decision logic for the "Auto" connection count — a
/// simplified IDM-style adaptive multi-connection controller.
///
/// Confined to one serial queue by the caller (`ChunkManager`). Feed it one
/// smoothed speed sample per second via ``record(speed:)``, signal server
/// stress via ``recordFailure(now:)``, and ask it, at most once per
/// `evaluationInterval`, for the connection count to switch to via
/// ``evaluate(currentConnections:hasPending:now:)``.
///
/// The policy combines four signals:
/// 1. **Latency (RTT)** and file size pick the cold-start connection count.
/// 2. A measured **single-connection throughput** (from the probe chunk)
///    estimates the initial count in one shot, replacing trial-and-error.
/// 3. **Retryable failures** (429/5xx/network) freeze upward probing so a
///    rate-limited server is not made worse by adding connections.
/// 4. **Gain magnitude** decides the probe step (big gains jump +2/+3).
///
/// It probes, keeps additions only when throughput actually grew, remembers
/// the best count, and converges once the best speed is stable. No timers or
/// I/O, so its behaviour is fully unit-testable from synthetic samples.
public struct AutoConnectionPolicy: Sendable {
    /// Lowest usable connection count.
    public let minConnections: Int
    /// Highest connection count the engine may use.
    public let maxConnections: Int
    /// A probe is kept only when steady speed grows by at least this fraction.
    public let gainThreshold: Double
    /// Minimum time between two connection changes. Defensive: with the default
    /// evaluation cadence (equal interval) it never actually blocks, but it
    /// keeps future, faster callers from oscillating.
    public let cooldown: TimeInterval
    /// How often ``evaluate`` may be called (the caller's timer cadence).
    public let evaluationInterval: TimeInterval
    /// Evaluations with no change before the policy declares itself converged.
    public let stableEvaluationsToConverge: Int
    /// Retryable failures inside `errorFreezeWindow` that freeze probing.
    public let errorFreezeThreshold: Int
    /// Window over which failures are counted.
    public let errorFreezeWindow: TimeInterval
    /// Time without failures after which the freeze lifts.
    public let errorFreezeRelease: TimeInterval
    /// Weight of the newest speed sample in the EMA (0..1). Higher = faster to
    /// react, lower = smoother.
    public let emaCoefficient: Double
    /// A connection count is reverted only when speed falls below this fraction
    /// of the best seen (regression detection).
    public let regressThreshold: Double
    /// Gain ratio at/above which the next probe jumps +3 connections.
    public let jumpThresholdHigh: Double
    /// Gain ratio at/above which the next probe jumps +2 connections.
    public let jumpThresholdLow: Double
    /// After converging, the policy re-probes upward this often, so it can pick
    /// up network improvements that arrived mid-download.
    public let reprobeInterval: TimeInterval

    public init(minConnections: Int = 1,
                maxConnections: Int = 16,
                gainThreshold: Double = 0.05,
                cooldown: TimeInterval = 3,
                evaluationInterval: TimeInterval = 3,
                stableEvaluationsToConverge: Int = 5,
                errorFreezeThreshold: Int = 3,
                errorFreezeWindow: TimeInterval = 15,
                errorFreezeRelease: TimeInterval = 30,
                emaCoefficient: Double = 0.5,
                regressThreshold: Double = 0.8,
                jumpThresholdHigh: Double = 1.3,
                jumpThresholdLow: Double = 1.15,
                reprobeInterval: TimeInterval = 30) {
        self.minConnections = max(1, minConnections)
        self.maxConnections = max(self.minConnections, maxConnections)
        self.gainThreshold = max(0, gainThreshold)
        self.cooldown = max(0, cooldown)
        self.evaluationInterval = max(0.1, evaluationInterval)
        self.stableEvaluationsToConverge = max(1, stableEvaluationsToConverge)
        self.errorFreezeThreshold = max(1, errorFreezeThreshold)
        self.errorFreezeWindow = max(0, errorFreezeWindow)
        self.errorFreezeRelease = max(0, errorFreezeRelease)
        self.emaCoefficient = min(1, max(0, emaCoefficient))
        self.regressThreshold = min(1, max(0, regressThreshold))
        self.jumpThresholdHigh = max(1, jumpThresholdHigh)
        self.jumpThresholdLow = max(1, jumpThresholdLow)
        self.reprobeInterval = max(0, reprobeInterval)
    }

    // MARK: - Cold-start counts

    /// Recommended starting connection count from file size and the probe's
    /// measured latency. High RTT hints at RTT/window-limited single
    /// connections, where more connections multiply throughput.
    public static func initialConnectionCount(fileSize: Int64, supportsResume: Bool, rtt: TimeInterval = 0) -> Int {
        guard supportsResume else { return 1 }
        let bySize: Int
        if fileSize < 1_048_576 { bySize = 1 }              // < 1 MiB
        else if fileSize < 16 * 1_048_576 { bySize = 2 }    // < 16 MiB
        else { bySize = 4 }                                 // ≥ 16 MiB
        if rtt >= 0.15 { return max(bySize, 6) }
        if rtt >= 0.05 { return max(bySize, 4) }
        return bySize
    }

    /// One-shot initial count from the probe's measured single-connection
    /// throughput. A low rate means per-connection caps or window limits, so
    /// more connections help; a high rate means the link is already fast, so
    /// few connections are needed. Clamped so tiny files never over-allocate.
    public static func informedInitialConnectionCount(singleConnRate: Int64, fileSize: Int64, rtt: TimeInterval = 0) -> Int {
        guard singleConnRate > 0 else {
            return initialConnectionCount(fileSize: fileSize, supportsResume: true, rtt: rtt)
        }
        let byRate: Int
        if singleConnRate < 512 * 1024 { byRate = 16 }
        else if singleConnRate < 1_048_576 { byRate = 12 }
        else if singleConnRate < 2_097_152 { byRate = 8 }
        else if singleConnRate < 5_242_880 { byRate = 4 }
        else { byRate = 2 }
        var count = byRate
        // Low measured single-connection rate + high latency: window-limited,
        // more connections multiply throughput.
        if singleConnRate < 1_048_576, rtt >= 0.15 { count = max(count, 6) }
        else if singleConnRate < 1_048_576, rtt >= 0.05 { count = max(count, 4) }
        // Small files have too few chunks to parallelize.
        if fileSize < 1_048_576 { count = min(count, 2) }
        else if fileSize < 16 * 1_048_576 { count = min(count, 4) }
        return min(16, max(1, count))
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
    private var convergedAt: Date?
    private var lastGainRatio: Double = 0
    private var failureTimes: [Date] = []
    private var lastFailureAt: Date?
    /// True while upward probing is frozen by a burst of retryable failures
    /// (429/5xx). Read-only; lets the engine and tests observe the state.
    public private(set) var isFrozen = false

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
        convergedAt = nil
        lastGainRatio = 0
        failureTimes = []
        lastFailureAt = nil
        isFrozen = false
    }

    /// Smoothes a new aggregate-throughput sample (one per second). Uses an
    /// exponential moving average to damp short-lived speed spikes/dips.
    public mutating func record(speed: Int64) {
        let sample = max(0, speed)
        if !hasSmoothed {
            smoothedSpeed = sample
            hasSmoothed = true
        } else {
            smoothedSpeed = Int64((Double(smoothedSpeed) * (1 - emaCoefficient)) + (Double(sample) * emaCoefficient))
        }
    }

    /// Records a retryable failure (429/5xx/network). A burst inside the freeze
    /// window freezes upward probing so a stressed server is not made worse.
    public mutating func recordFailure(now: Date = Date()) {
        let window = errorFreezeWindow
        failureTimes.append(now)
        failureTimes.removeAll { now.timeIntervalSince($0) > window }
        lastFailureAt = now
        if failureTimes.count >= errorFreezeThreshold {
            isFrozen = true
        }
    }

    /// Treats an informed one-shot jump (from the probe's measured rate) as a
    /// probe, so the next evaluation confirms it against the gain threshold
    /// instead of trusting the estimate blindly.
    public mutating func noteInformedProbe(from prevConnections: Int) {
        guard hasSmoothed else { return }
        // The current sample still reflects `prevConnections` (the jump has not
        // been measured yet), so record it as the best before the jump.
        if smoothedSpeed > bestSpeed {
            bestSpeed = smoothedSpeed
            bestConnections = max(1, prevConnections)
        }
        probePrevConnections = max(1, prevConnections)
        probePrevSpeed = smoothedSpeed
        isProbing = true
        stableCount = 0
    }

    /// Hard-caps the connection count at `count`, used when the server signals
    /// rate-limiting (HTTP 429) — a "one request at a time" constraint where the
    /// adaptive "more connections = more throughput" assumption is wrong. Also
    /// lowers `bestConnections` so a later freeze/regression never climbs back.
    public mutating func forceConcurrencyCeiling(_ count: Int) {
        let c = max(1, count)
        ceiling = c
        bestConnections = min(bestConnections, c)
        isProbing = false
        stableCount = 0
        isConverged = false
        convergedAt = nil
    }

    /// Called at most once per `evaluationInterval`. Returns the connection
    /// count to switch to, or `nil` to keep the current count.
    public mutating func evaluate(currentConnections: Int, hasPending: Bool, now: Date = Date()) -> Int? {
        guard hasSmoothed else { return nil }
        // Without queued chunks there is nothing new to parallelize.
        guard hasPending else { return nil }

        // Frozen: hold the count (dropping to the best known level) until the
        // error storm has passed.
        if isFrozen {
            if let last = lastFailureAt, now.timeIntervalSince(last) >= errorFreezeRelease {
                isFrozen = false
                failureTimes.removeAll()
            } else {
                if currentConnections > bestConnections {
                    return bestConnections
                }
                return nil
            }
        }

        // Revert to the best count if the current one is doing clearly worse.
        // Checked before the convergence guard so a mid-download slowdown is
        // still corrected after the policy has converged.
        if bestSpeed > 0, Double(smoothedSpeed) < Double(bestSpeed) * regressThreshold,
           currentConnections > bestConnections {
            lastChangeAt = now
            stableCount = 0
            lastGainRatio = 0
            isConverged = false
            convergedAt = nil
            return bestConnections
        }

        // Once converged, re-probe upward on a slow cadence so a network that
        // improved mid-download is picked up instead of locking the count.
        if isConverged {
            if let at = convergedAt, now.timeIntervalSince(at) >= reprobeInterval {
                isConverged = false
                convergedAt = nil
                stableCount = 0
                // Nudge the ceiling up one so the re-probe may climb past it.
                if ceiling != Int.max {
                    ceiling = Swift.min(ceiling + 1, maxConnections)
                }
            } else {
                return nil
            }
        }

        // Respect the cooldown between changes so decisions don't oscillate.
        if let last = lastChangeAt, now.timeIntervalSince(last) < cooldown { return nil }

        if smoothedSpeed > bestSpeed {
            bestSpeed = smoothedSpeed
            bestConnections = currentConnections
        }

        if isProbing {
            // Measure the probe: keep the added connection(s) only if they paid off.
            lastChangeAt = now
            stableCount = 0
            if Double(smoothedSpeed) >= Double(probePrevSpeed) * (1 + gainThreshold) {
                lastGainRatio = Double(smoothedSpeed) / Double(probePrevSpeed)
                isProbing = false
                return nil
            } else {
                // Diminishing returns — revert and remember this level as the ceiling.
                isProbing = false
                lastGainRatio = 0
                ceiling = probePrevConnections
                return probePrevConnections
            }
        }

        // Otherwise probe upward.
        guard smoothedSpeed > 0, currentConnections < maxConnections, currentConnections < ceiling else {
            stableCount += 1
            if stableCount >= stableEvaluationsToConverge {
                isConverged = true
                convergedAt = now
            }
            return nil
        }

        // Adaptive step: jump +2/+3 after strong previous gains to converge
        // faster on per-connection-throttled servers.
        let step: Int
        if lastGainRatio >= jumpThresholdHigh { step = 3 }
        else if lastGainRatio >= jumpThresholdLow { step = 2 }
        else { step = 1 }
        let next = Swift.min(currentConnections + step, ceiling)
        probePrevSpeed = smoothedSpeed
        probePrevConnections = currentConnections
        isProbing = true
        lastChangeAt = now
        stableCount = 0
        return next
    }
}
