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
        // +20% throughput -> keep the second connection.
        settle(&p, speed: 1200)
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(3)) == nil)
        // Next evaluation probes one higher.
        settle(&p, speed: 1200)
        #expect(p.evaluate(currentConnections: 2, hasPending: true, now: t0.addingTimeInterval(6)) == 3)
    }

    @Test func perConnectionThrottleStepsUpToMax() {
        // A server that throttles per connection yields linear aggregate gains,
        // so the policy keeps stepping up to the cap.
        var p = AutoConnectionPolicy(maxConnections: 8, gainThreshold: 0.05, cooldown: 3)
        var t = t0
        var conns = 1
        settle(&p, speed: 1000)
        for expected in 2...8 {
            #expect(p.evaluate(currentConnections: conns, hasPending: true, now: t) == expected)
            conns = expected
            t = t.addingTimeInterval(3)
            settle(&p, speed: Int64(conns) * 1000)
            #expect(p.evaluate(currentConnections: conns, hasPending: true, now: t) == nil)
            t = t.addingTimeInterval(3)
            settle(&p, speed: Int64(conns) * 1000)
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
}
