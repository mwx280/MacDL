import Testing
import Foundation
@testable import Aria2Desk

// MARK: - Download Model
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

// MARK: - DownloadStatus Display
@Suite struct DownloadStatusDisplayTests {
    @Test(arguments: [
        (DownloadStatus.active, "arrow.down.circle.fill"),
        (.paused, "pause.circle.fill"),
        (.waiting, "clock.fill"),
        (.completed, "checkmark.circle.fill"),
        (.stopped, "stop.circle.fill"),
        (.error, "exclamationmark.circle.fill"),
    ]) func displayIcon(status: DownloadStatus, expected: String) {
        #expect(status.displayIcon == expected)
    }

    @Test(arguments: [
        DownloadStatus.active,
        .paused,
        .waiting,
        .completed,
        .stopped,
        .error,
    ]) func displayColorNotClear(status: DownloadStatus) {
        #expect(status.displayColor != .clear)
    }

    @Test(arguments: [
        (DownloadStatus.active, "Active"),
        (.paused, "Paused"),
        (.waiting, "Waiting"),
        (.completed, "Completed"),
        (.stopped, "Stopped"),
        (.error, "Error"),
    ]) func labelKey(status: DownloadStatus, expected: String) {
        #expect(status.labelKey == expected)
    }
}

// MARK: - Download FileType Extensions
@Suite struct DownloadFileTypeTests {
    @Test(arguments: [
        ("video.iso", "opticaldisc"),
        ("movie.mkv", "film"),
        ("archive.zip", "shippingbox"),
        ("app.dmg", "app.dashed"),
        ("model.gguf", "cpu"),
        ("doc.pdf", "doc.richtext"),
        ("notes.txt", "doc.text"),
        ("photo.jpg", "photo"),
        ("song.mp3", "music.note"),
        ("unknown.xyz", "doc"),
    ]) func fileTypeIcon(filename: String, expected: String) {
        let d = Download(id: UUID(), filename: filename, url: "", totalSize: 0, downloadedSize: 0, downloadSpeed: 0, uploadSpeed: 0, status: .active, addedAt: Date())
        #expect(d.fileTypeIcon == expected)
    }

    @Test(arguments: [
        "video.iso",
        "movie.mkv",
        "archive.zip",
        "model.gguf",
        "doc.pdf",
        "unknown.xyz",
    ]) func fileTypeColorNotClear(filename: String) {
        let d = Download(id: UUID(), filename: filename, url: "", totalSize: 0, downloadedSize: 0, downloadSpeed: 0, uploadSpeed: 0, status: .active, addedAt: Date())
        #expect(d.fileTypeColor != .clear)
    }
}

// MARK: - LanguageManager
@Suite(.serialized) struct LanguageManagerTests {
    @Test func localizedEnglish() {
        LanguageManager.shared.selectedLanguage = .en
        #expect(LanguageManager.shared.localized("All Downloads") == "All Downloads")
    }

    @Test func localizedChinese() {
        LanguageManager.shared.selectedLanguage = .zh
        #expect(LanguageManager.shared.localized("All Downloads") == "所有下载")
    }

    @Test func localizedFallbackToKey() {
        LanguageManager.shared.selectedLanguage = .en
        #expect(LanguageManager.shared.localized("Nonexistent.Key.12345") == "Nonexistent.Key.12345")
    }
}

// MARK: - SidebarItem
@Suite struct SidebarItemTests {
    @Test func allItemsHaveTitleKey() {
        for item in SidebarItem.allCases { #expect(!item.titleKey.isEmpty) }
    }

    @Test func allItemsHaveIcon() {
        for item in SidebarItem.allCases { #expect(!item.icon.isEmpty) }
    }
}

// MARK: - Formatters
@Suite struct FormattersTests {
    @Test func formatSpeedZero() {
        let result = formatSpeed(0)
        #expect(!result.isEmpty)
        #expect(result.hasSuffix("/s"))
    }

    @Test func speedFormatterDoesNotCrash() {
        let result = formatSpeed(1_048_576)
        #expect(!result.isEmpty)
        #expect(result.hasSuffix("/s"))
    }

    @Test func formatSizeZero() {
        let result = formatSize(0)
        #expect(!result.isEmpty)
    }

    @Test func sizeFormatterDoesNotCrash() {
        let result = formatSize(1_048_576)
        #expect(!result.isEmpty)
        #expect(result.contains("MB"))
    }
}

// MARK: - SettingsStore
@Suite(.serialized) struct SettingsStoreTests {
    let store = SettingsStore.shared

    @Test func defaultMaxConnections() {
        #expect(store.maxConnections == 16)
    }

    @Test func defaultMaxConcurrentDownloads() {
        #expect(store.maxConcurrentDownloads == 5)
    }

    @Test func writeThenReadMaxConnections() {
        let original = store.maxConnections
        store.maxConnections = 32
        #expect(store.maxConnections == 32)
        store.maxConnections = original
    }

    @Test func writeThenReadSecretToken() {
        let original = store.secretToken
        store.secretToken = "test-token"
        #expect(store.secretToken == "test-token")
        store.secretToken = original
    }
}

// MARK: - ContentViewModel
@Suite struct ContentViewModelTests {
    @Test func filteredDownloadsAll() {
        let vm = ContentViewModel()
        let result = vm.filteredDownloads(for: .all)
        #expect(result.count == vm.downloads.count)
    }

    @Test func filteredDownloadsActive() {
        let vm = ContentViewModel()
        let result = vm.filteredDownloads(for: .active)
        #expect(result.allSatisfy { $0.status == .active })
    }

    @Test func filteredDownloadsCompleted() {
        let vm = ContentViewModel()
        let result = vm.filteredDownloads(for: .completed)
        #expect(result.allSatisfy { $0.status == .completed })
    }

    @Test func pauseAllChangesStatus() {
        let vm = ContentViewModel()
        let activeIds = Set(vm.downloads.filter { $0.status == .active }.map(\.id))
        guard !activeIds.isEmpty else { return }
        vm.selectedDownloads = activeIds
        vm.pauseAll()
        for id in activeIds {
            let d = vm.downloads.first { $0.id == id }
            #expect(d?.status == .paused)
        }
    }

    @Test func resumeAllChangesStatus() {
        let vm = ContentViewModel()
        let pausedIds = Set(vm.downloads.filter { $0.status == .paused || $0.status == .waiting }.map(\.id))
        guard !pausedIds.isEmpty else { return }
        vm.selectedDownloads = pausedIds
        vm.resumeAll()
        for id in pausedIds {
            let d = vm.downloads.first { $0.id == id }
            #expect(d?.status == .active)
        }
    }

    @Test func addDownloadIncreasesCount() {
        let vm = ContentViewModel()
        let before = vm.downloads.count
        vm.addDownload(url: "https://example.com/file.zip")
        #expect(vm.downloads.count == before + 1)
        #expect(vm.downloads.last?.filename == "file.zip")
    }

    @Test func addDownloadWithNoPathInURL() {
        let vm = ContentViewModel()
        let before = vm.downloads.count
        vm.addDownload(url: "magnet:?xt=urn:btih:abc123")
        #expect(vm.downloads.count == before + 1)
    }

    @Test func computeTotalSpeed() {
        let vm = ContentViewModel()
        let expected = vm.downloads.reduce(0) { $0 + $1.downloadSpeed }
        #expect(vm.totalSpeed == expected)
    }

    @Test func computeTotalUpload() {
        let vm = ContentViewModel()
        let expected = vm.downloads.reduce(0) { $0 + $1.uploadSpeed }
        #expect(vm.totalUpload == expected)
    }

    @Test func filteredDownloadsEmptyForInvalidSidebar() {
        let vm = ContentViewModel()
        vm.downloads = []
        for item in SidebarItem.allCases {
            let result = vm.filteredDownloads(for: item)
            #expect(result.isEmpty)
        }
    }
}

// MARK: - Appearance
@Suite struct AppearanceTests {
    @Test func appearanceAllCasesExist() {
        #expect(Appearance.allCases.count == 3)
    }

    @Test func appearanceDisplayKeyNonEmpty() {
        for a in Appearance.allCases { #expect(!a.displayKey.isEmpty) }
    }

    @Test func appearanceSystemRawValue() {
        #expect(Appearance.system.rawValue == "system")
    }
}

// MARK: - RPCConfig
@Suite struct RPCConfigTests {
    @Test func appSupportDirectoryIsNonEmpty() {
        let config = RPCConfig()
        #expect(!config.appSupportDirectory.isEmpty)
        #expect(config.appSupportDirectory.hasPrefix("/"))
    }

    @Test func aria2SessionPathContainsSession() {
        let config = RPCConfig()
        #expect(config.aria2SessionPath.hasSuffix("/aria2.session"))
    }

    @Test func downloadDirectoryContainsDownloads() {
        let config = RPCConfig()
        #expect(config.downloadDirectory.hasSuffix("/downloads"))
    }

    @Test func defaultHostIsLocalhost() {
        let config = RPCConfig()
        #expect(config.host == "localhost")
    }
}

// MARK: - EngineState
@Suite struct EngineStateTests {
    @Test(arguments: [
        EngineState.stopped,
        .starting,
        .running,
        .error("test"),
    ]) func engineStateLabelNonEmpty(state: EngineState) {
        #expect(!state.label.isEmpty)
    }

    @Test func errorStateLabel() {
        #expect(EngineState.error("x").label == "Error")
    }

    @Test func runningStateLabel() {
        #expect(EngineState.running.label == "Running")
    }
}

// MARK: - PreviewContent
@Suite struct PreviewContentTests {
    @Test func previewContentHasItems() {
        #expect(!PreviewContent.downloads.isEmpty)
    }
}
