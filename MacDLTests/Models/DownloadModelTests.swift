import Testing
import Foundation
import MacDLCore
@testable import MacDL

@Suite struct DownloadModelTests {
    @Test func progressCappedAtOne() {
        let d = Download(id: UUID(), filename: "t.bin", url: "https://e.com/t.bin", totalSize: 100, downloadedSize: 150, downloadSpeed: 0, status: .completed, addedAt: Date())
        #expect(d.progress == 1.0)
    }

    @Test func progressPartial() {
        let d = Download(id: UUID(), filename: "t.bin", url: "https://e.com/t.bin", totalSize: 200, downloadedSize: 50, downloadSpeed: 0, status: .active, addedAt: Date())
        #expect(d.progress == 0.25)
    }

    @Test func progressZeroWhenTotalZero() {
        let d = Download(id: UUID(), filename: "t.bin", url: "https://e.com/t.bin", totalSize: 0, downloadedSize: 0, downloadSpeed: 0, status: .active, addedAt: Date())
        #expect(d.progress == 0)
    }

    @Test func decodesWithoutSupportsResume() throws {
        let json = """
        {"id": "\(UUID().uuidString)", "filename": "a.bin", "url": "https://e.com/a.bin", "totalSize": 10, "downloadedSize": 0, "downloadSpeed": 0, "status": "active", "addedAt": 0, "chunkSize": 262144, "maxConcurrentChunks": 1, "chunks": []}
        """
        let d = try JSONDecoder().decode(Download.self, from: Data(json.utf8))
        #expect(d.supportsResume == nil)
    }

    @Test func codableRoundTripsSupportsResume() throws {
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin", supportsResume: false)
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(Download.self, from: data)
        #expect(decoded.supportsResume == false)
    }

    @Test func codableRoundTripsPriorityFlags() throws {
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin", isPriorityDownload: true, pausedForPriority: false)
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(Download.self, from: data)
        #expect(decoded.isPriorityDownload == true)
        #expect(decoded.pausedForPriority == false)
    }
}
