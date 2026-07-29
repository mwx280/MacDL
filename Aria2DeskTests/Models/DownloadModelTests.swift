import Testing
import Foundation
@testable import Aria2Desk

@Suite struct DownloadModelTests {
    @Test func progressCappedAtOne() {
        let d = Download(id: UUID(), filename: "t.bin", url: "https://e.com/t.bin", totalSize: 100, downloadedSize: 150, downloadSpeed: 0, uploadSpeed: 0, status: .completed, addedAt: Date())
        #expect(d.progress == 1.0)
    }

    @Test func progressPartial() {
        let d = Download(id: UUID(), filename: "t.bin", url: "https://e.com/t.bin", totalSize: 200, downloadedSize: 50, downloadSpeed: 0, uploadSpeed: 0, status: .active, addedAt: Date())
        #expect(d.progress == 0.25)
    }

    @Test func progressZeroWhenTotalZero() {
        let d = Download(id: UUID(), filename: "t.bin", url: "https://e.com/t.bin", totalSize: 0, downloadedSize: 0, downloadSpeed: 0, uploadSpeed: 0, status: .active, addedAt: Date())
        #expect(d.progress == 0)
    }
}
