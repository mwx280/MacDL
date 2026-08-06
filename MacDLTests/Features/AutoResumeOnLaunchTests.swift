import Testing
import Foundation
import MacDLCore
@testable import MacDL

// Auto-resume on launch: when enabled, only the tasks that were downloading at
// quit time are restarted; manually paused ones stay paused.
@MainActor @Suite(.serialized) struct AutoResumeOnLaunchTests {
    private func makeSettings(autoResume: Bool) -> SettingsStore {
        let suite = "auto-resume-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        settings.autoResumeOnLaunch = autoResume
        return settings
    }

    private func makePersistence() -> DownloadPersistence {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("auto-resume-tests-\(UUID().uuidString)", isDirectory: true)
        return DownloadPersistence(fileURL: dir.appendingPathComponent("downloads.json"))
    }

    @Test func settingDefaultsToOff() {
        let defaults = UserDefaults(suiteName: "auto-resume-default-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.autoResumeOnLaunch == false)
    }

    @Test func settingRoundTrips() {
        let settings = makeSettings(autoResume: true)
        #expect(settings.autoResumeOnLaunch == true)
        settings.autoResumeOnLaunch = false
        #expect(settings.autoResumeOnLaunch == false)
    }

    @Test func enabledResumesPreviouslyActiveOnly() {
        let engine = FakeEngine()
        let persistence = makePersistence()
        let active = Download(filename: "resume-a.bin", url: "https://example.com/a.bin", status: .active)
        let paused = Download(filename: "resume-b.bin", url: "https://example.com/b.bin", status: .paused)
        persistence.saveImmediately([active, paused])
        let vm = ContentViewModel(engine: engine, persistence: persistence, settings: makeSettings(autoResume: true))
        let a = vm.downloads.first { $0.id == active.id }
        let b = vm.downloads.first { $0.id == paused.id }
        #expect(a?.status == .active)
        #expect(engine.started.contains(active.id))
        #expect(b?.status == .paused)
        #expect(!engine.started.contains(paused.id))
    }

    @Test func disabledLeavesAllPaused() {
        let engine = FakeEngine()
        let persistence = makePersistence()
        let active = Download(filename: "resume-c.bin", url: "https://example.com/c.bin", status: .active)
        persistence.saveImmediately([active])
        let vm = ContentViewModel(engine: engine, persistence: persistence, settings: makeSettings(autoResume: false))
        let c = vm.downloads.first { $0.id == active.id }
        #expect(c?.status == .paused)
        #expect(engine.started.isEmpty)
    }
}
