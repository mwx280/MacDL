import Testing
import Foundation
@testable import MacDL

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
