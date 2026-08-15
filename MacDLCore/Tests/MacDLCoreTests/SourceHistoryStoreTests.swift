import Testing
import Foundation
@testable import MacDLCore

@Suite struct SourceHistoryStoreTests {
    @Test func unknownHostReturnsNil() {
        SourceHistoryStore.shared.setFileURL(nil)
        SourceHistoryStore.shared.removeAll()
        #expect(SourceHistoryStore.shared.history(for: "unknown.example") == nil)
    }

    @Test func firstRecordSetsInitialValues() {
        SourceHistoryStore.shared.setFileURL(nil)
        SourceHistoryStore.shared.removeAll()
        SourceHistoryStore.shared.record(host: "a.example", bandwidth: 1000, rtt: 0.1,
                                         success: true, supportsRange: true)
        let h = SourceHistoryStore.shared.history(for: "a.example")
        #expect(h != nil)
        #expect(h?.avgBandwidth == 1000)
        #expect(h?.avgRTT == 0.1)
        #expect(h?.successCount == 1)
        #expect(h?.failureCount == 0)
        #expect(h?.supportsRange == true)
        #expect(h?.sampleCount == 1)
    }

    @Test func repeatedRecordsMergeEWMA() {
        SourceHistoryStore.shared.setFileURL(nil)
        SourceHistoryStore.shared.removeAll()
        SourceHistoryStore.shared.record(host: "a.example", bandwidth: 1000, rtt: 0.1,
                                         success: true, supportsRange: true)
        SourceHistoryStore.shared.record(host: "a.example", bandwidth: 2000, rtt: 0.2,
                                         success: false, supportsRange: true)
        let h = SourceHistoryStore.shared.history(for: "a.example")
        #expect(h != nil)
        // 0.8 * 1000 + 0.2 * 2000 = 1200
        #expect(h?.avgBandwidth == 1200)
        // 0.8 * 0.1 + 0.2 * 0.2 = 0.12
        #expect(abs((h?.avgRTT ?? 0) - 0.12) < 0.0001)
        #expect(h?.successCount == 1)
        #expect(h?.failureCount == 1)
        #expect(h?.sampleCount == 2)
        #expect(h?.successRate == 0.5)
    }

    @Test func hostsAreIndependent() {
        SourceHistoryStore.shared.setFileURL(nil)
        SourceHistoryStore.shared.removeAll()
        SourceHistoryStore.shared.record(host: "a.example", bandwidth: 1000, rtt: 0.1, success: true, supportsRange: nil)
        SourceHistoryStore.shared.record(host: "b.example", bandwidth: 5000, rtt: 0.05, success: true, supportsRange: nil)
        #expect(SourceHistoryStore.shared.history(for: "a.example")?.avgBandwidth == 1000)
        #expect(SourceHistoryStore.shared.history(for: "b.example")?.avgBandwidth == 5000)
    }

    @Test func persistsAndReloadsFromFile() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macdl-history-test")
            .appendingPathComponent("history.json")
        try? FileManager.default.removeItem(at: url)
        SourceHistoryStore.shared.setFileURL(url)
        SourceHistoryStore.shared.removeAll()
        SourceHistoryStore.shared.record(host: "a.example", bandwidth: 3000, rtt: 0.08,
                                         success: true, supportsRange: true)
        SourceHistoryStore.shared.flush()
        // Reload from disk into a fresh store (setFileURL re-reads the file).
        SourceHistoryStore.shared.removeAll()
        SourceHistoryStore.shared.setFileURL(url)
        let h = SourceHistoryStore.shared.history(for: "a.example")
        #expect(h?.avgBandwidth == 3000)
        #expect(h?.supportsRange == true)
        try? FileManager.default.removeItem(at: url)
        SourceHistoryStore.shared.setFileURL(nil)
    }
}
