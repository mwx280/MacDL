import Testing
@testable import Aria2Desk

@Suite struct SidebarItemTests {
    @Test func allItemsHaveTitleKey() {
        for item in SidebarItem.allCases { #expect(!item.titleKey.isEmpty) }
    }

    @Test func allItemsHaveIcon() {
        for item in SidebarItem.allCases { #expect(!item.icon.isEmpty) }
    }
}
