import Testing
import Foundation
@testable import MacDL

@Suite(.serialized) struct SettingsStoreTests {
    let store = SettingsStore.shared

    @Test func defaultMaxConnections() {
        let original = store.maxConnections
        store.maxConnections = 0
        #expect(store.maxConnections == 8)
        store.maxConnections = original
    }

    @Test func defaultMaxConcurrentDownloads() {
        #expect(store.maxConcurrentDownloads == 5)
    }

    @Test func writeThenReadMaxConnections() {
        let original = store.maxConnections
        store.maxConnections = 4
        #expect(store.maxConnections == 4)
        store.maxConnections = original
    }

    @Test func defaultMaxDownloadSpeed() {
        let original = store.maxDownloadSpeed
        store.maxDownloadSpeed = 0
        #expect(store.maxDownloadSpeed == 0)
        store.maxDownloadSpeed = original
    }

    @Test func writeThenReadMaxDownloadSpeed() {
        let original = store.maxDownloadSpeed
        store.maxDownloadSpeed = 1_048_576
        #expect(store.maxDownloadSpeed == 1_048_576)
        store.maxDownloadSpeed = original
    }

}
