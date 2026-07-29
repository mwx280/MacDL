import Testing
import Foundation
@testable import Aria2Desk

@Suite struct RPCConfigTests {
    @Test func appSupportDirectoryIsNonEmpty() {
        let config = RPCConfig()
        #expect(!config.appSupportDirectory.isEmpty)
        #expect(config.appSupportDirectory.hasPrefix("/"))
    }

    @Test func aria2SessionPathContainsSession() {
        let config = RPCConfig()
        #expect(config.aria2SessionPath.hasSuffix("/aria2.session"))
    }

    @Test func downloadDirectoryContainsDownloads() {
        let config = RPCConfig()
        #expect(config.downloadDirectory.hasSuffix("/downloads"))
    }

    @Test func defaultHostIsLocalhost() {
        let config = RPCConfig()
        #expect(config.host == "localhost")
    }
}
