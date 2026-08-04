import Testing
import Foundation
import MacDLCore
@testable import MacDL

@Suite struct DownloadPersistenceTests {
    private func tempFile() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("persistence-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("downloads.json")
    }

    @Test func loadMigratesLegacyEnglishErrorMessages() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        // Legacy data: no errorKey field, English errorMessage persisted verbatim.
        let legacy = """
        [
          {"id": "\(UUID().uuidString)", "filename": "a.bin", "url": "https://e.com/a.bin", "totalSize": 10, "downloadedSize": 0, "downloadSpeed": 0, "status": "error", "addedAt": 0, "chunkSize": 262144, "maxConcurrentChunks": 1, "chunks": [], "errorMessage": "Download file has been deleted"},
          {"id": "\(UUID().uuidString)", "filename": "b.bin", "url": "https://e.com/b.bin", "totalSize": 10, "downloadedSize": 0, "downloadSpeed": 0, "status": "error", "addedAt": 0, "chunkSize": 262144, "maxConcurrentChunks": 1, "chunks": [], "errorMessage": "HTTP 500"}
        ]
        """
        try legacy.write(to: url, atomically: true, encoding: .utf8)

        let loaded = DownloadPersistence(fileURL: url).load()
        #expect(loaded.count == 2)
        // Known English message is mapped to its key so it re-localizes.
        #expect(loaded[0].errorKey == "Download file has been deleted")
        // Unmapped formatted message keeps its persisted text (no key).
        #expect(loaded[1].errorKey == nil)
        #expect(loaded[1].errorMessage == "HTTP 500")
    }
}
