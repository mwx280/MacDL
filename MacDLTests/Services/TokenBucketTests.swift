import Testing
import Foundation
@testable import MacDL

@Suite struct TokenBucketTests {
    @Test func unlimitedWhenRateZero() {
        let bucket = TokenBucket(rate: 0)
        #expect(bucket.take(100_000) == true)
    }

    @Test func stoppedReturnsFalse() {
        let bucket = TokenBucket(rate: 1_000)
        bucket.stop()
        #expect(bucket.take(100) == false)
    }

    @Test func takeWaitsForRate() {
        let bucket = TokenBucket(rate: 1_000)
        let start = Date()
        #expect(bucket.take(500) == true)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed >= 0.4)
    }

    @Test func accumulatedTokensConsumedImmediately() {
        let bucket = TokenBucket(rate: 1_000)
        Thread.sleep(forTimeInterval: 1.0)
        let start = Date()
        #expect(bucket.take(500) == true)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.2)
    }

    @Test func setRateUpdatesLimit() {
        let bucket = TokenBucket(rate: 1_000)
        bucket.setRate(10_000)
        Thread.sleep(forTimeInterval: 0.3)
        let start = Date()
        #expect(bucket.take(2_000) == true)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 0.2)
    }

    @Test func resetReusesBucket() {
        let bucket = TokenBucket(rate: 1_000)
        bucket.stop()
        #expect(bucket.take(100) == false)
        bucket.reset(rate: 0)
        #expect(bucket.take(100) == true)
    }
}
