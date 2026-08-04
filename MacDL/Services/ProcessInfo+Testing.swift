import Foundation

// Single source of truth for "are we running under the test host?".
// Xcode injects XCTestConfigurationFilePath into the test host process;
// NSClassFromString covers contexts where the env var is absent but XCTest
// is loaded. Centralized so the real engine, disk and notification center are
// never touched during tests.
extension ProcessInfo {
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil || NSClassFromString("XCTestCase") != nil
    }
}
