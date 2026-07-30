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
}
