import Testing
import Foundation
import MacDLCore
@testable import MacDL

@MainActor
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

    @Test func codableRoundTripsSaveBookmark() throws {
        let bookmark = Data([0x01, 0x02, 0x03, 0x04])
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin", savePath: "/tmp/x", saveBookmark: bookmark)
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(Download.self, from: data)
        #expect(decoded.saveBookmark == bookmark)
        #expect(decoded.savePath == "/tmp/x")
    }

    @Test func decodesWithoutSaveBookmark() throws {
        let json = """
        {"id": "\(UUID().uuidString)", "filename": "a.bin", "url": "https://e.com/a.bin", "totalSize": 10, "downloadedSize": 0, "downloadSpeed": 0, "status": "active", "addedAt": 0, "chunkSize": 262144, "maxConcurrentChunks": 1, "chunks": []}
        """
        let d = try JSONDecoder().decode(Download.self, from: Data(json.utf8))
        #expect(d.saveBookmark == nil)
        #expect(d.savePath == nil)
    }

    @Test func decodesWithoutErrorKey() throws {
        // Legacy JSON: errorMessage persisted in English, no errorKey field.
        let json = """
        {"id": "\(UUID().uuidString)", "filename": "a.bin", "url": "https://e.com/a.bin", "totalSize": 10, "downloadedSize": 0, "downloadSpeed": 0, "status": "error", "addedAt": 0, "chunkSize": 262144, "maxConcurrentChunks": 1, "chunks": [], "errorMessage": "Download file has been deleted"}
        """
        let d = try JSONDecoder().decode(Download.self, from: Data(json.utf8))
        #expect(d.errorKey == nil)
        #expect(d.errorMessage == "Download file has been deleted")
    }

    @Test func codableRoundTripsErrorKey() throws {
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin", errorMessage: "x", errorKey: "Download file has been deleted")
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(Download.self, from: data)
        #expect(decoded.errorKey == "Download file has been deleted")
    }

    @Test func displayedErrorMessageLocalizesKey() {
        let original = LanguageManager.shared.selectedLanguage
        defer { LanguageManager.shared.selectedLanguage = original }
        LanguageManager.shared.selectedLanguage = .zh
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin", errorMessage: "stale english", errorKey: "Download file has been deleted")
        #expect(DownloadErrorText.text(for: d) == "下载文件已被删除")
    }

    @Test func displayedErrorMessageFallsBackToPersistedText() {
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin", errorMessage: "custom detail", errorKey: nil)
        #expect(DownloadErrorText.text(for: d) == "custom detail")
    }
}
