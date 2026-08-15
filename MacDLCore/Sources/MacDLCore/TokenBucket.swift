import Foundation

// Shared byte-level token bucket for smooth throttling across all chunks.
// Event-driven: waiters sleep on an NSCondition and are woken by stop()/reset(),
// instead of polling every 20 ms.
/// Byte-level throttle shared by all chunks of a download. Waiters sleep on an
/// `NSCondition` until enough tokens accrue, and are woken early by
/// `stop()`/`reset()` instead of polling.
/// @unchecked Sendable: all mutable state is guarded by `NSCondition`.
public final class TokenBucket: @unchecked Sendable {
    private let condition = NSCondition()
    private var rate: Double
    private var tokens: Double = 0
    private var lastRefill = Date()
    private var stopped = false

    /// Creates a bucket. `rate` is in bytes/second; 0 means unlimited.
    public init(rate: Double) {
        self.rate = max(0, rate)
    }

    /// Changes the refill rate; wakes any waiting consumer to re-evaluate.
    public func setRate(_ newRate: Double) {
        condition.lock()
        rate = max(0, newRate)
        condition.signal()
        condition.unlock()
    }

    /// Stops the bucket; `take()` returns false from now on until `reset()`.
    public func stop() {
        condition.lock()
        stopped = true
        condition.broadcast()
        condition.unlock()
    }

    /// Re-activates the bucket with a fresh rate and empty token pool.
    public func reset(rate newRate: Double) {
        condition.lock()
        stopped = false
        rate = max(0, newRate)
        tokens = 0
        lastRefill = Date()
        condition.signal()
        condition.unlock()
    }

    /// Blocks until `amount` bytes can be consumed, or until `stop()` is
    /// called. Returns false when stopped.
    @discardableResult
    public func take(_ amount: Double) -> Bool {
        condition.lock()
        while true {
            if stopped {
                condition.unlock()
                return false
            }
            if rate <= 0 {
                condition.unlock()
                return true
            }
            let now = Date()
            let elapsed = now.timeIntervalSince(lastRefill)
            if elapsed > 0 {
                tokens += rate * elapsed
                lastRefill = now
                // Token cap: allows ~2s of burst, but at least 1MB so a single take(<=1MB) always succeeds and low-speed throttling can't deadlock
                tokens = min(tokens, max(rate * EngineConstants.bucketTokenCapMultiplier, EngineConstants.bucketTokenMinCap))
            }
            if tokens >= amount {
                tokens -= amount
                condition.unlock()
                return true
            }
            // Sleep precisely until enough tokens accrue (no polling); a rate
            // change or stop() wakes us earlier to re-evaluate.
            let deficit = amount - tokens
            let wait = deficit / rate
            condition.wait(until: Date().addingTimeInterval(wait))
        }
    }
}
