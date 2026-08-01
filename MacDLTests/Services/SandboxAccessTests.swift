import Testing
import Foundation
import MacDLCore
@testable import MacDL

@Suite struct SandboxAccessTests {
    @Test func defaultDownloadDirIsRealDownloads() {
        let dir = AppConfig.defaultDownloadDir
        #expect(FileManager.default.fileExists(atPath: dir))
        // Must resolve to the real user Downloads, not the sandbox container.
        #expect(!dir.contains("/Library/Containers/"))
        #expect(dir.hasSuffix("/Downloads"))
    }

    @Test func defaultPathNeedsNoBookmark() {
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin", savePath: AppConfig.defaultDownloadDir)
        #expect(SandboxAccess.shared.beginAccess(for: d) == true)
        SandboxAccess.shared.endAccess(for: d.id)
    }

    @Test func customPathWithoutBookmarkFails() {
        let d = Download(filename: "a.bin", url: "https://e.com/a.bin", savePath: "/some/other/dir")
        #expect(SandboxAccess.shared.beginAccess(for: d) == false)
    }

    @Test func bookmarkRoundTripsAndGrantsAccess() throws {
        let dir = NSTemporaryDirectory() + "/sandbox-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let url = URL(fileURLWithPath: dir, isDirectory: true)
        let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)

        var stale = false
        let resolved = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        #expect(resolved.standardizedFileURL.path == url.standardizedFileURL.path)

        let d = Download(filename: "a.bin", url: "https://e.com/a.bin", savePath: dir, saveBookmark: bookmark)
        #expect(SandboxAccess.shared.beginAccess(for: d) == true)
        // Should be able to create a file in the folder while access is held.
        let probe = dir + "/probe.txt"
        let ok = FileManager.default.createFile(atPath: probe, contents: Data("x".utf8))
        SandboxAccess.shared.endAccess(for: d.id)
        #expect(ok == true)
        try? FileManager.default.removeItem(atPath: probe)
    }

    @Test func settingsBookmarkPersists() {
        let suite = "SandboxAccessTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        let bookmark = Data([0xAA, 0xBB])
        settings.downloadPath = "/tmp/custom-dir"
        settings.downloadPathBookmark = bookmark
        let reread = SettingsStore(defaults: defaults)
        #expect(reread.downloadPath == "/tmp/custom-dir")
        #expect(reread.downloadPathBookmark == bookmark)
    }
}
