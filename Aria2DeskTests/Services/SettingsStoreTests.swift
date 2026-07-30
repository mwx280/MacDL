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

    @Test func defaultMaxDownloadSpeed() {
        let original = store.maxDownloadSpeed
        store.maxDownloadSpeed = 0
        #expect(store.maxDownloadSpeed == 0)
        store.maxDownloadSpeed = original
    }

    @Test func defaultMaxUploadSpeed() {
        let original = store.maxUploadSpeed
        store.maxUploadSpeed = 0
        #expect(store.maxUploadSpeed == 0)
        store.maxUploadSpeed = original
    }

    @Test func writeThenReadMaxDownloadSpeed() {
        let original = store.maxDownloadSpeed
        store.maxDownloadSpeed = 1_048_576
        #expect(store.maxDownloadSpeed == 1_048_576)
        store.maxDownloadSpeed = original
    }

    @Test func writeThenReadMaxUploadSpeed() {
        let original = store.maxUploadSpeed
        store.maxUploadSpeed = 512_000
        #expect(store.maxUploadSpeed == 512_000)
        store.maxUploadSpeed = original
    }
}
