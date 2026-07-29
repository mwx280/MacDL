import Testing
import Foundation
@testable import Aria2Desk

@Suite(.serialized) struct LanguageManagerTests {
    @Test func localizedEnglish() {
        let manager = LanguageManager.shared
        manager.selectedLanguage = .en
        #expect(manager.localized("All Downloads") == "All Downloads")
    }

    @Test func localizedChinese() {
        let manager = LanguageManager.shared
        manager.selectedLanguage = .zh
        #expect(manager.localized("All Downloads") == "所有下载")
    }

    @Test func localizedFallbackToKey() {
        let manager = LanguageManager.shared
        manager.selectedLanguage = .en
        #expect(manager.localized("Nonexistent.Key.12345") == "Nonexistent.Key.12345")
    }
}

struct DownloadTests {
    @Test func progressCappedAtOne() {
        let download = Download(
            id: UUID(),
            filename: "test.bin",
            url: "https://example.com/test.bin",
            totalSize: 100,
            downloadedSize: 150,
            downloadSpeed: 0,
            uploadSpeed: 0,
            status: .completed,
            addedAt: Date()
        )
        #expect(download.progress == 1.0)
    }

    @Test func progressPartial() {
        let download = Download(
            id: UUID(),
            filename: "test.bin",
            url: "https://example.com/test.bin",
            totalSize: 200,
            downloadedSize: 50,
            downloadSpeed: 0,
            uploadSpeed: 0,
            status: .active,
            addedAt: Date()
        )
        #expect(download.progress == 0.25)
    }

    @Test func progressZeroWhenTotalZero() {
        let download = Download(
            id: UUID(),
            filename: "test.bin",
            url: "https://example.com/test.bin",
            totalSize: 0,
            downloadedSize: 0,
            downloadSpeed: 0,
            uploadSpeed: 0,
            status: .active,
            addedAt: Date()
        )
        #expect(download.progress == 0)
    }
}

struct SidebarItemTests {
    @Test func allItemsHaveTitleKey() {
        for item in SidebarItem.allCases {
            #expect(!item.titleKey.isEmpty)
        }
    }

    @Test func allItemsHaveIcon() {
        for item in SidebarItem.allCases {
            #expect(!item.icon.isEmpty)
        }
    }

    @Test func settingsTitleKey() {
        #expect(SidebarItem.settings.titleKey == "Settings")
    }
}
