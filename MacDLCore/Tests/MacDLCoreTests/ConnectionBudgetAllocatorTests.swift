import Testing
import Foundation
@testable import MacDLCore

@Suite struct ConnectionBudgetAllocatorTests {
    @Test func unregisteredDownloadGetsPerDownloadCap() {
        let a = ConnectionBudgetAllocator(totalBudget: 32, perDownloadCap: 16)
        let id = UUID()
        #expect(a.share(for: id) == 16)
    }

    @Test func singleDownloadGetsCappedBudget() {
        let a = ConnectionBudgetAllocator(totalBudget: 32, perDownloadCap: 16)
        let id = UUID()
        a.register(id)
        // 32 for one download, but capped at 16.
        #expect(a.share(for: id) == 16)
    }

    @Test func shareSplitsEvenlyAcrossDownloads() {
        let a = ConnectionBudgetAllocator(totalBudget: 32, perDownloadCap: 16)
        let ids = [UUID(), UUID(), UUID()]
        ids.forEach { a.register($0) }
        // 32 / 3 = 10 each.
        for id in ids { #expect(a.share(for: id) == 10) }
    }

    @Test func removingDownloadRestoresShare() {
        let a = ConnectionBudgetAllocator(totalBudget: 32, perDownloadCap: 16)
        let a1 = UUID(), a2 = UUID()
        a.register(a1)
        a.register(a2)
        #expect(a.share(for: a1) == 16)
        a.remove(a1)
        #expect(a.share(for: a2) == 16)
    }

    @Test func registerIsIdempotent() {
        let a = ConnectionBudgetAllocator(totalBudget: 32, perDownloadCap: 16)
        let id = UUID()
        a.register(id)
        a.register(id)
        #expect(a.participantCount == 1)
        #expect(a.share(for: id) == 16)
    }

    @Test func smallBudgetNeverDropsBelowOne() {
        let a = ConnectionBudgetAllocator(totalBudget: 4, perDownloadCap: 16)
        let ids = [UUID(), UUID(), UUID(), UUID(), UUID(), UUID()]
        ids.forEach { a.register($0) }
        for id in ids { #expect(a.share(for: id) >= 1) }
    }
}
