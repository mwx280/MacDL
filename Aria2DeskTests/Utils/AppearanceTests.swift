import Testing
@testable import Aria2Desk

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
