import Testing
import Foundation
@testable import MacDL

@Suite(.serialized) struct LanguageManagerTests {
    @Test func localizedEnglish() {
        let original = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .en
        #expect(LanguageManager.shared.localized("All Downloads") == "All Downloads")
        LanguageManager.shared.selectedLanguage = original
    }

    @Test func localizedChinese() {
        let original = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .zh
        #expect(LanguageManager.shared.localized("All Downloads") == "所有下载")
        LanguageManager.shared.selectedLanguage = original
    }

    @Test func localizedFallbackToKey() {
        let original = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .en
        #expect(LanguageManager.shared.localized("Nonexistent.Key.12345") == "Nonexistent.Key.12345")
        LanguageManager.shared.selectedLanguage = original
    }

    @Test func newlyAddedKeysHaveChineseTranslations() {
        let original = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .zh
        #expect(LanguageManager.shared.localized("Invalid URL") == "无效的链接")
        #expect(LanguageManager.shared.localized("OK") == "确定")
        #expect(LanguageManager.shared.localized("Version %@ (build %@)") == "版本 %@ (构建 %@)")
        #expect(LanguageManager.shared.localized("HTTP %ld") == "HTTP %ld")
        LanguageManager.shared.selectedLanguage = original
    }

    @Test func newlyAddedKeysFallBackToEnglishKeys() {
        let original = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .en
        #expect(LanguageManager.shared.localized("Invalid URL") == "Invalid URL")
        #expect(LanguageManager.shared.localized("Version %@ (build %@)") == "Version %@ (build %@)")
        LanguageManager.shared.selectedLanguage = original
    }

    @Test func fileDeletedErrorMessageIsTranslated() {
        let original = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .zh
        #expect(LanguageManager.shared.localized("Download file has been deleted") == "下载文件已被删除")
        LanguageManager.shared.selectedLanguage = .en
        #expect(LanguageManager.shared.localized("Download file has been deleted") == "Download file has been deleted")
        LanguageManager.shared.selectedLanguage = original
    }
}
