import Testing
import Foundation
@testable import Aria2Desk

@Suite struct PreviewContentTests {
    @Test func previewContentHasItems() {
        #expect(!PreviewContent.downloads.isEmpty)
    }
}
