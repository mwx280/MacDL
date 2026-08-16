import Testing
import Foundation
@testable import MacDLCore

// The cross-download scheduler: FIFO waiting, concurrency cap, promotion on
// finish/capacity growth/removal.

@Suite struct DownloadSchedulerTests {

    @Test func runsUpToCapacityImmediately() {
        let s = DownloadScheduler(capacity: 2)
        #expect(s.schedule(UUID()) == true)
        #expect(s.schedule(UUID()) == true)
        #expect(s.activeCount == 2)
    }

    @Test func queuesOverCapacityInFifoOrder() {
        let s = DownloadScheduler(capacity: 1)
        let a = UUID(), b = UUID(), c = UUID()
        #expect(s.schedule(a) == true)
        #expect(s.schedule(b) == false)
        #expect(s.schedule(c) == false)
        #expect(s.isRunning(a))
        #expect(s.isWaiting(b))
        #expect(s.isWaiting(c))
        #expect(s.waitingCount == 2)
    }

    @Test func finishPromotesFifoNext() {
        let s = DownloadScheduler(capacity: 1)
        let a = UUID(), b = UUID(), c = UUID()
        _ = s.schedule(a)
        _ = s.schedule(b)
        _ = s.schedule(c)
        // a finishes -> b promoted (FIFO).
        #expect(s.finished(a) == [b])
        #expect(s.isRunning(b))
        #expect(s.isWaiting(c))
        // b finishes -> c promoted.
        #expect(s.finished(b) == [c])
        #expect(s.isRunning(c))
    }

    @Test func growingCapacityPromotesAllAvailable() {
        let s = DownloadScheduler(capacity: 1)
        let a = UUID(), b = UUID(), c = UUID()
        _ = s.schedule(a)
        _ = s.schedule(b)
        _ = s.schedule(c)
        // Cap 1 -> 3 promotes the two queued downloads.
        #expect(s.setCapacity(3).sorted() == [b, c].sorted())
        #expect(s.activeCount == 3)
        #expect(s.waitingCount == 0)
    }

    @Test func shrinkingCapacityKeepsRunning() {
        let s = DownloadScheduler(capacity: 3)
        let a = UUID(), b = UUID()
        _ = s.schedule(a)
        _ = s.schedule(b)
        // Shrinking does not evict running downloads; it only stops new ones.
        #expect(s.setCapacity(1).isEmpty)
        #expect(s.isRunning(a))
        #expect(s.isRunning(b))
    }

    @Test func removingWaitingDoesNotPromote() {
        let s = DownloadScheduler(capacity: 1)
        let a = UUID(), b = UUID()
        _ = s.schedule(a)
        _ = s.schedule(b)
        #expect(s.remove(b).isEmpty)
        #expect(s.isWaiting(b) == false)
        #expect(s.waitingCount == 0)
        // Removing a running download frees a slot.
        #expect(s.remove(a) == [])
    }

    @Test func removingRunningPromotesNext() {
        let s = DownloadScheduler(capacity: 1)
        let a = UUID(), b = UUID()
        _ = s.schedule(a)
        _ = s.schedule(b)
        #expect(s.remove(a) == [b])
        #expect(s.isRunning(b))
    }

    @Test func discardNeverPromotes() {
        let s = DownloadScheduler(capacity: 1)
        let a = UUID(), b = UUID()
        _ = s.schedule(a)
        _ = s.schedule(b)
        // Pausing/deleting a running download must not start a queued one.
        s.discard(a)
        #expect(s.isRunning(a) == false)
        #expect(s.isWaiting(b) == true)
        // Discarding the queued one leaves nothing behind.
        s.discard(b)
        #expect(s.isWaiting(b) == false)
        #expect(s.waitingCount == 0)
    }

    @Test func forceRunBypassesCapacity() {
        let s = DownloadScheduler(capacity: 1)
        let a = UUID(), b = UUID(), c = UUID()
        _ = s.schedule(a)
        _ = s.schedule(b)
        _ = s.schedule(c)
        // Resume a queued download out of turn (app resume bypasses the cap).
        s.forceRun(b)
        #expect(s.isRunning(a))
        #expect(s.isRunning(b))
        #expect(s.waitingCount == 1)
        // Both slots are now full; finishing a does not promote c.
        #expect(s.finished(a).isEmpty)
        #expect(s.isWaiting(c))
        #expect(s.isRunning(b))
    }

    @Test func finishRemovesPendingWaitingEntry() {
        // finished() on a queued (never-running) id must not promote it later.
        let s = DownloadScheduler(capacity: 1)
        let a = UUID(), b = UUID()
        _ = s.schedule(a)
        _ = s.schedule(b)
        #expect(s.finished(b).isEmpty)
        // a finishes, nothing queued behind it.
        #expect(s.finished(a).isEmpty)
        #expect(s.waitingCount == 0)
    }

    @Test func enqueueKeepsWaitingUntilSlotFrees() {
        let s = DownloadScheduler(capacity: 1)
        let a = UUID(), b = UUID()
        _ = s.schedule(a)
        s.enqueue(b)
        #expect(s.isWaiting(b))
        #expect(s.finished(a) == [b])
        #expect(s.isRunning(b))
    }

    @Test func enqueueDoesNotDuplicate() {
        let s = DownloadScheduler(capacity: 1)
        let a = UUID()
        _ = s.schedule(a)
        s.enqueue(a)
        s.enqueue(a)
        #expect(s.activeCount == 1)
        #expect(s.waitingCount == 0)
    }
}
