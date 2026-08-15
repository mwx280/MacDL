import Testing
import Foundation
@testable import MacDLCore

@Suite struct AutoConnectionPolicyTests {

    private func settle(_ policy: inout AutoConnectionPolicy, speed: Int64, iterations: Int = 5) {
        for _ in 0..<iterations { policy.record(speed: speed) }
    }

    private let t0 = Date(timeIntervalSince1970: 0)

    // MARK: - Initial count heuristic

    @Test func initialNonResumableUsesOneConnection() {
        #expect(AutoConnectionPolicy.initialConnectionCount(fileSize: 100 * 1024 * 1024, supportsResume: false) == 1)
    }

    @Test func initialCountScalesWithFileSize() {
        #expect(AutoConnectionPolicy.initialConnectionCount(fileSize: 0, supportsResume: true) == 1)
        #expect(AutoConnectionPolicy.initialConnectionCount(fileSize: 1_048_575, supportsResume: true) == 1)
        #expect(AutoConnectionPolicy.initialConnectionCount(fileSize: 1_048_576, supportsResume: true) == 2)
        #expect(AutoConnectionPolicy.initialConnectionCount(fileSize: 16 * 1_048_576 - 1, supportsResume: true) == 2)
        #expect(AutoConnectionPolicy.initialConnectionCount(fileSize: 16 * 1_048_576, supportsResume: true) == 4)
        #expect(AutoConnectionPolicy.initialConnectionCount(fileSize: 4 * 1024 * 1024 * 1024, supportsResume: true) == 4)
    }

    // MARK: - Adaptive stepping

    @Test func noGainRevertsProbe() {
        var p = AutoConnectionPolicy(cooldown: 3)
        settle(&p, speed: 1000)
        let probe = p.evaluate(currentConnections: 1, hasPending: true, now: t0)
        #expect(probe == 2)
        // Same throughput with 2 connections: no gain -> revert to 1.
        settle(&p, speed: 1000)
        let revert = p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(3))
        #expect(revert == 1)
    }

    @Test func gainKeepsProbeAndProbesAgain() {
        var p = AutoConnectionPolicy(cooldown: 3)
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t0) == 2)
        // +10% throughput -> keep the second connection (gain < jump threshold).
        settle(&p, speed: 1100)
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(3)) == nil)
        // Next evaluation probes one higher.
        settle(&p, speed: 1100)
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(6)) == 3)
    }

    @Test func perConnectionThrottleReachesMax() {
        // A server that throttles per connection yields linear aggregate gains,
        // so the policy keeps stepping (with jumps) up to the cap.
        var p = AutoConnectionPolicy(maxConnections: 8, gainThreshold: 0.05, cooldown: 3)
        var t = t0
        var conns = 1
        settle(&p, speed: 1000)
        for _ in 0..<40 {
            if let next = p.evaluate(currentConnections: conns, hasPending: true, now: t) {
                conns = next
            }
            t = t.addingTimeInterval(3)
            settle(&p, speed: Int64(conns) * 1000)
            if conns >= 8 { break }
        }
        #expect(conns == 8)
        #expect(p.evaluate(currentConnections: 8, hasPending: true, now: t) == nil)
    }

    @Test func ceilingPreventsRepeatedFailedProbes() {
        var p = AutoConnectionPolicy(cooldown: 3)
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t0) == 2)
        settle(&p, speed: 1000)
        // No gain -> revert to 1 and remember 1 as the ceiling.
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(3)) == 1)
        // Even after the cooldown, it must never probe above the ceiling again.
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t0.addingTimeInterval(6)) == nil)
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t0.addingTimeInterval(9)) == nil)
    }

    @Test func noPendingWorkNeverIncreases() {
        var p = AutoConnectionPolicy(cooldown: 3)
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: false, now: t0) == nil)
        #expect(p.evaluate(currentConnections: 1, hasPending: false, now: t0.addingTimeInterval(6)) == nil)
    }

    @Test func convergesAndStopsAdjusting() {
        var p = AutoConnectionPolicy(maxConnections: 8, cooldown: 3, stableEvaluationsToConverge: 5)
        var t = t0
        settle(&p, speed: 1000)
        // Blocked at max with no gain from the start.
        for _ in 0..<6 {
            let next = p.evaluate(currentConnections: 8, hasPending: true, now: t)
            #expect(next == nil)
            t = t.addingTimeInterval(3)
            settle(&p, speed: 1000)
        }
        // Even after convergence it stays put.
        #expect(p.evaluate(currentConnections: 8, hasPending: true, now: t) == nil)
    }

    @Test func cooldownThrottlesChanges() {
        var p = AutoConnectionPolicy(cooldown: 3)
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t0) == 2)
        // Change again within the cooldown: allowed only after the interval.
        settle(&p, speed: 1100)
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(1)) == nil)
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(3)) == nil)
    }

    // MARK: - Latency-weighted cold start

    @Test func initialCountWeightsRTT() {
        // 8 MiB file, low latency → 2; moderate RTT → 4; high RTT → 6.
        #expect(AutoConnectionPolicy.initialConnectionCount(fileSize: 8 * 1_048_576, supportsResume: true, rtt: 0) == 2)
        #expect(AutoConnectionPolicy.initialConnectionCount(fileSize: 8 * 1_048_576, supportsResume: true, rtt: 0.08) == 4)
        #expect(AutoConnectionPolicy.initialConnectionCount(fileSize: 8 * 1_048_576, supportsResume: true, rtt: 0.2) == 6)
        // Non-resumable always wins with a single connection.
        #expect(AutoConnectionPolicy.initialConnectionCount(fileSize: 8 * 1_048_576, supportsResume: false, rtt: 0.5) == 1)
    }

    // MARK: - Informed one-shot estimate

    @Test func informedEstimateTracksPerConnectionCap() {
        // Low measured single-connection rate → many connections.
        #expect(AutoConnectionPolicy.informedInitialConnectionCount(singleConnRate: 300 * 1024, fileSize: 32 * 1_048_576, rtt: 0) == 16)
        // High rate → the link is fast, few connections.
        #expect(AutoConnectionPolicy.informedInitialConnectionCount(singleConnRate: 3 * 1_048_576, fileSize: 8 * 1_048_576, rtt: 0) == 4)
        #expect(AutoConnectionPolicy.informedInitialConnectionCount(singleConnRate: 30 * 1_048_576, fileSize: 8 * 1_048_576, rtt: 0) == 2)
        // Low rate + high RTT → latency bump applies.
        #expect(AutoConnectionPolicy.informedInitialConnectionCount(singleConnRate: 800 * 1024, fileSize: 32 * 1_048_576, rtt: 0.2) == 12)
        // Tiny file never over-allocates even on a slow link.
        #expect(AutoConnectionPolicy.informedInitialConnectionCount(singleConnRate: 300 * 1024, fileSize: 1_000, rtt: 0) == 2)
    }

    // MARK: - Error freeze

    @Test func errorBurstFreezesProbing() {
        var p = AutoConnectionPolicy(cooldown: 3, errorFreezeThreshold: 3, errorFreezeWindow: 15, errorFreezeRelease: 30)
        settle(&p, speed: 1000)
        // Start probing up, then a failure burst hits.
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t0) == 2)
        p.recordFailure(now: t0.addingTimeInterval(1))
        p.recordFailure(now: t0.addingTimeInterval(2))
        p.recordFailure(now: t0.addingTimeInterval(3)) // third failure → frozen
        settle(&p, speed: 1100)
        // Frozen: drop from 2 back to the best known count (1)...
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(6)) == 1)
        // ...and stay put while the storm is recent.
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t0.addingTimeInterval(9)) == nil)
    }

    @Test func freezeReleasesAfterQuietPeriod() {
        var p = AutoConnectionPolicy(cooldown: 3, errorFreezeThreshold: 1, errorFreezeWindow: 15, errorFreezeRelease: 30)
        settle(&p, speed: 1000)
        p.recordFailure(now: t0.addingTimeInterval(1)) // single failure, threshold 1 → frozen
        // Frozen with current == best: no change.
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t0.addingTimeInterval(6)) == nil)
        // After the release window with no new failures, probing resumes.
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t0.addingTimeInterval(60)) == 2)
    }

    // MARK: - Adaptive jump

    @Test func strongGainJumpsMultipleConnections() {
        var p = AutoConnectionPolicy(cooldown: 3)
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t0) == 2)
        // 2x gain on the probe → next step is +3.
        settle(&p, speed: 2000)
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(3)) == nil)
        settle(&p, speed: 2000)
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(6)) == 5)
    }

    @Test func moderateGainJumpsTwoConnections() {
        var p = AutoConnectionPolicy(cooldown: 3)
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t0) == 2)
        // 1.2x gain → next step is +2.
        settle(&p, speed: 1200)
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(3)) == nil)
        settle(&p, speed: 1200)
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(6)) == 4)
    }

    // MARK: - Convergence re-probe

    @Test func reprobesAfterConvergence() {
        var p = AutoConnectionPolicy(cooldown: 3, stableEvaluationsToConverge: 2, reprobeInterval: 30)
        var t = t0
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t) == 2) // probe up
        t = t.addingTimeInterval(3)
        settle(&p, speed: 1000) // no gain
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t) == 1) // revert, ceiling = 1
        // Stable at 1 → converge after two quiet evaluations.
        t = t.addingTimeInterval(3)
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t) == nil)
        t = t.addingTimeInterval(3)
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t) == nil) // converged
        // Within the re-probe window the count stays put.
        t = t.addingTimeInterval(3)
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t) == nil)
        // After the re-probe interval the policy climbs past the old ceiling.
        t = t.addingTimeInterval(30)
        settle(&p, speed: 1000)
        #expect(p.evaluate(currentConnections: 1, hasPending: true, now: t) == 2)
    }

    // MARK: - Informed probe confirmation

    @Test func informedProbeRevertsWithoutGain() {
        var p = AutoConnectionPolicy(cooldown: 3)
        settle(&p, speed: 1000)
        p.noteInformedProbe(from: 1) // informed jump to 2
        settle(&p, speed: 1000) // 2 connections but no gain
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(3)) == 1)
    }

    @Test func informedProbeKeepsOnGain() {
        var p = AutoConnectionPolicy(cooldown: 3)
        settle(&p, speed: 1000)
        p.noteInformedProbe(from: 1) // informed jump to 2
        settle(&p, speed: 1200) // 20% gain → keep
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(3)) == nil)
    }
}
