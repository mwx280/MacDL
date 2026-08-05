import Testing
import Foundation
@testable import MacDL

@MainActor
@Suite struct ProcessInfoTests {
    @Test func isRunningTestsTrueUnderTestHost() {
        // The app test host always runs under XCTest, so this must be true.
        // It guards against the real engine/persistence/notifier being touched
        // while tests run (see ProcessInfo.isRunningTests).
        #expect(ProcessInfo.isRunningTests)
    }
}
