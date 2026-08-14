import Testing
import Foundation
@testable import MacDL

@MainActor
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

    @Test func launchAtLoginPersists() {
        let original = store.launchAtLogin
        store.launchAtLogin = true
        #expect(store.launchAtLogin == true)
        store.launchAtLogin = false
        #expect(store.launchAtLogin == false)
        store.launchAtLogin = original
    }

    @Test func hideDockIconOnClosePersists() {
        let original = store.hideDockIconOnClose
        store.hideDockIconOnClose = true
        #expect(store.hideDockIconOnClose == true)
        store.hideDockIconOnClose = false
        #expect(store.hideDockIconOnClose == false)
        store.hideDockIconOnClose = original
    }

    @Test func autoUpdateDefaultsOn() {
        let original = store.autoUpdate
        store.autoUpdate = false
        #expect(store.autoUpdate == false)
        store.autoUpdate = true
        #expect(store.autoUpdate == true)
        store.autoUpdate = original
    }

    @Test func notifyTogglesDefaultOnAndPersist() {
        let pairs: [(String, () -> Bool, (Bool) -> Void)] = [
            ("notifyStart", { store.notifyStart }, { store.notifyStart = $0 }),
            ("notifyCompleted", { store.notifyCompleted }, { store.notifyCompleted = $0 }),
            ("notifyFailed", { store.notifyFailed }, { store.notifyFailed = $0 }),
            ("notifyRedownload", { store.notifyRedownload }, { store.notifyRedownload = $0 }),
            ("notifyLaunch", { store.notifyLaunch }, { store.notifyLaunch = $0 }),
        ]
        for (_, get, set) in pairs {
            let original = get()
            set(false)
            #expect(get() == false)
            set(true)
            #expect(get() == true)
            set(original)
        }
    }

    @Test func autoUpdateDefaultsTrueForFreshDefaults() {
        let fresh = SettingsStore(defaults: UserDefaults(suiteName: "test-auto-\(UUID().uuidString)")!)
        #expect(fresh.autoUpdate == true)
        #expect(fresh.notifyStart == true)
        #expect(fresh.notifyCompleted == true)
        #expect(fresh.notifyFailed == true)
        #expect(fresh.notifyRedownload == true)
        #expect(fresh.notifyLaunch == true)
        #expect(fresh.launchInBackground == true)
    }

    @Test func launchInBackgroundDefaultsOnAndPersists() {
        let original = store.launchInBackground
        store.launchInBackground = false
        #expect(store.launchInBackground == false)
        store.launchInBackground = true
        #expect(store.launchInBackground == true)
        store.launchInBackground = original
    }

}
