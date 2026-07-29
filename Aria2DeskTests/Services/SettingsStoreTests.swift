import Testing
import Foundation
@testable import Aria2Desk

@Suite(.serialized) struct SettingsStoreTests {
    let store = SettingsStore.shared

    @Test func defaultMaxConnections() {
        #expect(store.maxConnections == 16)
    }

    @Test func defaultMaxConcurrentDownloads() {
        #expect(store.maxConcurrentDownloads == 5)
    }

    @Test func writeThenReadMaxConnections() {
        let original = store.maxConnections
        store.maxConnections = 32
        #expect(store.maxConnections == 32)
        store.maxConnections = original
    }

    @Test func writeThenReadSecretToken() {
        let original = store.secretToken
        store.secretToken = "test-token"
        #expect(store.secretToken == "test-token")
        store.secretToken = original
    }
}
