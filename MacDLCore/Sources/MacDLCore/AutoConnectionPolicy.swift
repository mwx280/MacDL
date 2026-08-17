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
    /// A connection count is reverted only when the recent-window average falls
    /// below this fraction of the best seen (regression detection).
    public let regressThreshold: Double
    /// Samples required before sustained throughput regression can trigger a
    /// connection rollback. Samples arrive roughly once per second.
    public let regressionWindowSize: Int
    /// Direction reversals inside `oscillationWindow` that trip the circuit
    /// breaker. Reversals (not raw changes) are counted so a healthy monotonic
    /// climb to the optimum never trips it.
    public let oscillationThreshold: Int
    /// Sliding window over which direction reversals are counted.
    public let oscillationWindow: TimeInterval
    /// Connection count the policy locks to once tripped (never above this).
    public let tripConnectionCap: Int
    /// Gain ratio at/above which the next probe jumps +3 connections.
    public let jumpThresholdHigh: Double
    /// Gain ratio at/above which the next probe jumps +2 connections.
    public let jumpThresholdLow: Double
    /// After converging, the policy re-probes upward this often, so it can pick
    /// up network improvements that arrived mid-download. This is the base
    /// interval; a run of no-gain probes backs it off exponentially (see
    /// `noGainBackoffThreshold` / `noGainReprobeCap`).
    public let reprobeInterval: TimeInterval
    /// Consecutive no-gain probes before the re-probe interval starts backing
    /// off and the probe step drops to a single connection.
    public let noGainBackoffThreshold: Int
    /// Upper bound on the backed-off re-probe interval.
    public let noGainReprobeCap: TimeInterval

    public init(minConnections: Int = 1,
                maxConnections: Int = 16,
                gainThreshold: Double = 0.05,
                cooldown: TimeInterval = 3,
                evaluationInterval: TimeInterval = 3,
                stableEvaluationsToConverge: Int = 5,
                errorFreezeThreshold: Int = 3,
                errorFreezeWindow: TimeInterval = 15,
                errorFreezeRelease: TimeInterval = 30,
                emaCoefficient: Double = 0.3,
                regressThreshold: Double = 0.8,
                regressionWindowSize: Int = 5,
                oscillationThreshold: Int = 4,
                oscillationWindow: TimeInterval = 60,
                tripConnectionCap: Int = 4,
                jumpThresholdHigh: Double = 1.3,
                jumpThresholdLow: Double = 1.15,
                reprobeInterval: TimeInterval = 30,
                noGainBackoffThreshold: Int = 2,
                noGainReprobeCap: TimeInterval = 600) {
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
        self.regressionWindowSize = max(1, regressionWindowSize)
        self.oscillationThreshold = max(1, oscillationThreshold)
        self.oscillationWindow = max(0, oscillationWindow)
        self.tripConnectionCap = max(1, tripConnectionCap)
        self.jumpThresholdHigh = max(1, jumpThresholdHigh)
        self.jumpThresholdLow = max(1, jumpThresholdLow)
        self.reprobeInterval = max(0, reprobeInterval)
        self.noGainBackoffThreshold = max(1, noGainBackoffThreshold)
        self.noGainReprobeCap = max(self.reprobeInterval, noGainReprobeCap)
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
        // Moderate RTT still benefits from a floor: window-limited single
        // connections multiply throughput with a few more connections.
        if singleConnRate < 1_048_576, rtt >= 0.05, rtt < 0.15 { count = max(count, 4) }
        // Very high RTT is BDP-limited, not bandwidth-limited. Overshooting to
        // the max connection count on such a link causes TCP contention and
        // unstable aggregate throughput, so cap the one-shot estimate and let
        // the adaptive staircase explore upward from a saner starting point.
        if rtt >= 0.15 { count = min(count, rtt >= 0.5 ? 8 : 12) }
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
    /// Consecutive non-probing evaluations where smoothed speed beat the best.
    /// Prevents a transient spike at a high connection count from promoting
    /// `bestConnections` and dead-coding the regression rollback.
    private var bestStreak = 0
    /// Non-probing evaluations above `bestSpeed` before `bestConnections` is
    /// promoted to the current count.
    private let bestPromoteStreak = 3
    private var ceiling = Int.max
    private var isProbing = false
    private var probePrevSpeed: Int64 = 0
    private var probePrevConnections: Int = 1
    private var lastChangeAt: Date?
    private var stableCount = 0
    private var isConverged = false
    private var convergedAt: Date?
    private var lastGainRatio: Double = 0
    private var regressionSamples: [Int64] = []
    private var regressionSampleTotal: Double = 0
    private var failureTimes: [Date] = []
    private var lastFailureAt: Date?
    /// Consecutive no-gain probes. Once it reaches `noGainBackoffThreshold`,
    /// the re-probe interval backs off and the probe step drops to one. Read-only
    /// so the engine and tests can observe the throttle/saturation signal.
    public private(set) var consecutiveNoGain = 0
    /// True while upward probing is frozen by a burst of retryable failures
    /// (429/5xx). Read-only; lets the engine and tests observe the state.
    public private(set) var isFrozen = false
    /// True once the adaptive loop oscillated and locked itself down for the
    /// rest of the download. Read-only; lets the engine and tests observe it.
    public private(set) var isTripped = false
    private var reversalTimes: [Date] = []
    private var lastChangeDirection: Bool?

    /// Resets all adaptive state (used when auto mode is re-entered).
    public mutating func reset() {
        hasSmoothed = false
        smoothedSpeed = 0
        bestSpeed = 0
        bestConnections = 1
        bestStreak = 0
        ceiling = Int.max
        isProbing = false
        probePrevSpeed = 0
        probePrevConnections = 1
        lastChangeAt = nil
        stableCount = 0
        isConverged = false
        convergedAt = nil
        lastGainRatio = 0
        clearRegressionWindow()
        failureTimes = []
        lastFailureAt = nil
        isFrozen = false
        consecutiveNoGain = 0
        isTripped = false
        reversalTimes = []
        lastChangeDirection = nil
    }

    /// Clears only the circuit breaker (trip + oscillation history), keeping
    /// the learned best count and convergence state. Called on pause/resume,
    /// connection-mode changes and speed-limit changes so the download gets a
    /// fresh chance instead of staying locked down.
    public mutating func resetCircuitBreaker() {
        isTripped = false
        reversalTimes = []
        lastChangeDirection = nil
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
        regressionSamples.append(sample)
        regressionSampleTotal += Double(sample)
        if regressionSamples.count > regressionWindowSize {
            regressionSampleTotal -= Double(regressionSamples.removeFirst())
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
        clearRegressionWindow()
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
        clearRegressionWindow()
    }

    /// Called at most once per `evaluationInterval`. Returns the connection
    /// count to switch to, or `nil` to keep the current count.
    public mutating func evaluate(currentConnections: Int, hasPending: Bool, now: Date = Date()) -> Int? {
        guard hasSmoothed else { return nil }
        // Without queued chunks there is nothing new to parallelize.
        guard hasPending else { return nil }

        // Circuit breaker: once the loop has oscillated it stays locked down
        // for the rest of the download, until reset by pause/resume, a
        // connection-mode change or a speed-limit change.
        guard !isTripped else { return nil }

        // Frozen: hold the count (dropping to the best known level) until the
        // error storm has passed.
        if isFrozen {
            if let last = lastFailureAt, now.timeIntervalSince(last) >= errorFreezeRelease {
                isFrozen = false
                failureTimes.removeAll()
            } else {
                if currentConnections > bestConnections {
                    return applyChange(bestConnections, from: currentConnections, now: now)
                }
                return nil
            }
        }

        // Revert to the best count if the current one is doing clearly worse.
        // Checked before the convergence guard so a mid-download slowdown is
        // still corrected after the policy has converged.
        if hasSustainedRegression(against: bestSpeed),
           currentConnections > bestConnections {
            lastChangeAt = now
            stableCount = 0
            lastGainRatio = 0
            isProbing = false
            isConverged = false
            convergedAt = nil
            clearRegressionWindow()
            return applyChange(bestConnections, from: currentConnections, now: now)
        }

        // Once converged, re-probe upward on a slow cadence so a network that
        // improved mid-download is picked up instead of locking the count. A run
        // of no-gain probes backs the cadence off so a capped link (speed limit
        // or saturated network) is re-tested ever more rarely instead of churning.
        if isConverged {
            if let at = convergedAt, now.timeIntervalSince(at) >= effectiveReprobeInterval() {
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
            // Only promote `bestConnections` after a sustained, non-probing run
            // above the previous best. A transient spike at a high connection
            // count must not rewrite `bestConnections`, or the regression
            // rollback (`currentConnections > bestConnections`) can never fire.
            if !isProbing {
                bestStreak += 1
                if bestStreak >= bestPromoteStreak {
                    bestConnections = currentConnections
                    bestStreak = 0
                }
            }
        } else if !isProbing {
            bestStreak = 0
        }

        if isProbing {
            // Measure the probe: keep the added connection(s) only if they paid off.
            lastChangeAt = now
            stableCount = 0
            if Double(smoothedSpeed) >= Double(probePrevSpeed) * (1 + gainThreshold) {
                lastGainRatio = Double(smoothedSpeed) / Double(probePrevSpeed)
                isProbing = false
                consecutiveNoGain = 0
                clearRegressionWindow()
                return nil
            } else {
                // Diminishing returns — revert and remember this level as the ceiling.
                isProbing = false
                lastGainRatio = 0
                ceiling = probePrevConnections
                consecutiveNoGain += 1
                clearRegressionWindow()
                return applyChange(probePrevConnections, from: currentConnections, now: now)
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
        // faster on per-connection-throttled servers. Once a capped link has
        // burned several no-gain probes, back off to a single-connection step so
        // re-probes stay cheap.
        let rawStep: Int
        if consecutiveNoGain >= noGainBackoffThreshold { rawStep = 1 }
        else if lastGainRatio >= jumpThresholdHigh { rawStep = 3 }
        else if lastGainRatio >= jumpThresholdLow { rawStep = 2 }
        else { rawStep = 1 }
        // Defensive clamps: the probe step stays within 1...3 and the result
        // never exceeds the configured connection ceiling.
        let step = Swift.max(1, Swift.min(3, rawStep))
        let next = Swift.min(Swift.min(currentConnections + step, ceiling), maxConnections)
        probePrevSpeed = smoothedSpeed
        probePrevConnections = currentConnections
        isProbing = true
        lastChangeAt = now
        stableCount = 0
        clearRegressionWindow()
        return applyChange(next, from: currentConnections, now: now)
    }

    /// Requires a complete window so a short dip cannot trigger a rollback.
    /// The mean represents sustained throughput; using the minimum would make a
    /// single bad sample poison the entire window.
    private func hasSustainedRegression(against referenceSpeed: Int64) -> Bool {
        guard referenceSpeed > 0, regressionSamples.count == regressionWindowSize else { return false }
        let average = regressionSampleTotal / Double(regressionWindowSize)
        return average < Double(referenceSpeed) * regressThreshold
    }

    private mutating func clearRegressionWindow() {
        regressionSamples.removeAll(keepingCapacity: true)
        regressionSampleTotal = 0
    }

    /// Records the direction of a connection change and trips the circuit
    /// breaker once the loop reverses direction too many times inside
    /// `oscillationWindow`. Reversals (not raw changes) are counted so a
    /// healthy monotonic climb never trips it. On trip the in-flight probe is
    /// abandoned and the policy locks to a conservative count.
    private mutating func applyChange(_ newCount: Int, from current: Int, now: Date) -> Int {
        let up = newCount > current
        if let last = lastChangeDirection, last != up {
            reversalTimes.append(now)
            let window = oscillationWindow
            reversalTimes.removeAll { now.timeIntervalSince($0) > window }
            if reversalTimes.count >= oscillationThreshold {
                isTripped = true
                isProbing = false
                stableCount = 0
                isConverged = false
                convergedAt = nil
                return tripConnectionCount()
            }
        }
        lastChangeDirection = up
        return newCount
    }

    /// The connection count the policy locks to once tripped: the learned best,
    /// capped at `tripConnectionCap` so a wildly oscillating download settles
    /// conservatively.
    private func tripConnectionCount() -> Int {
        Swift.max(1, Swift.min(bestConnections, tripConnectionCap))
    }

    /// The re-probe cadence after convergence, backing off exponentially once a
    /// capped link has burned `noGainBackoffThreshold` no-gain probes.
    private func effectiveReprobeInterval() -> TimeInterval {
        guard consecutiveNoGain >= noGainBackoffThreshold else { return reprobeInterval }
        let extra = consecutiveNoGain - noGainBackoffThreshold + 1
        return Swift.min(reprobeInterval * pow(2, Double(extra)), noGainReprobeCap)
    }
}
