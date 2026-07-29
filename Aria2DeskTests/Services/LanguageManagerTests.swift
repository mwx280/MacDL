import Testing
import Foundation
@testable import Aria2Desk

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
