import Testing
import Foundation
@testable import MacDLCore

@Suite struct SourceTests {
    private let t0 = Date(timeIntervalSince1970: 0)

    @Test func sourceAvailableByDefault() {
        let s = Source(url: URL(string: "https://a.example/f")!)
        #expect(s.isAvailable(at: t0))
    }

    @Test func failuresBelowThresholdKeepSourceAvailable() {
        var s = Source(url: URL(string: "https://a.example/f")!)
        s.recordFailure(now: t0, threshold: 3, cooldown: 30)
        s.recordFailure(now: t0.addingTimeInterval(1), threshold: 3, cooldown: 30)
        #expect(s.isAvailable(at: t0.addingTimeInterval(2)))
    }

    @Test func thresholdFailuresTriggerCooldown() {
        var s = Source(url: URL(string: "https://a.example/f")!)
        s.recordFailure(now: t0, threshold: 3, cooldown: 30)
        s.recordFailure(now: t0.addingTimeInterval(1), threshold: 3, cooldown: 30)
        s.recordFailure(now: t0.addingTimeInterval(2), threshold: 3, cooldown: 30)
        #expect(!s.isAvailable(at: t0.addingTimeInterval(3)))
    }

    @Test func cooldownExpires() {
        var s = Source(url: URL(string: "https://a.example/f")!)
        s.recordFailure(now: t0, threshold: 1, cooldown: 30)
        #expect(!s.isAvailable(at: t0.addingTimeInterval(1)))
        #expect(s.isAvailable(at: t0.addingTimeInterval(31)))
    }

    @Test func successClearsFailureStreakAndCooldown() {
        var s = Source(url: URL(string: "https://a.example/f")!)
        s.recordFailure(now: t0, threshold: 1, cooldown: 30)
        #expect(!s.isAvailable(at: t0.addingTimeInterval(1)))
        s.recordSuccess()
        #expect(s.isAvailable(at: t0.addingTimeInterval(1)))
    }

    @Test func throughputMergesEWMA() {
        var s = Source(url: URL(string: "https://a.example/f")!)
        s.recordThroughput(1000)
        #expect(s.avgThroughput == 1000)
        s.recordThroughput(2000)
        // 0.7 * 1000 + 0.3 * 2000 = 1300
        #expect(s.avgThroughput == 1300)
        s.recordThroughput(-5)
        #expect(s.avgThroughput > 0)
    }
}
