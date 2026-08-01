import Testing
import Foundation
import UserNotifications
import MacDLCore
@testable import MacDL

// Inject FakeEngine to verify ContentViewModel's action logic against the engine, no real network needed.
@Suite(.serialized) struct ContentViewModelEngineTests {
    private func makePersistence() -> DownloadPersistence {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vm-tests-\(UUID().uuidString)", isDirectory: true)
        return DownloadPersistence(fileURL: dir.appendingPathComponent("downloads.json"))
    }

    private func makeVM(engine: FakeEngine) -> ContentViewModel {
        ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore())
    }

    private func makeVM(engine: FakeEngine, maxConcurrentDownloads: Int) -> ContentViewModel {
        let suite = "ContentViewModelEngineTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        settings.maxConcurrentDownloads = maxConcurrentDownloads
        return ContentViewModel(engine: engine, persistence: makePersistence(), settings: settings)
    }

    @Test func addDownloadStartsEngine() {
        let engine = FakeEngine()
        let vm = makeVM(engine: engine)
        let url = "https://example.com/engine-a.bin"
        vm.addDownload(url: url)
        let d = vm.downloads.first { $0.url == url }
        #expect(d?.status == .active)
        #expect(d != nil && engine.started.contains(d!.id))
    }

    @Test func addDownloadWaitsOverConcurrencyLimit() {
        let engine = FakeEngine()
        let vm = makeVM(engine: engine, maxConcurrentDownloads: 2)
        vm.addDownload(url: "https://example.com/wait-a.bin")
        vm.addDownload(url: "https://example.com/wait-b.bin")
        vm.addDownload(url: "https://example.com/wait-c.bin")
        let a = vm.downloads.first { $0.url == "https://example.com/wait-a.bin" }
        let b = vm.downloads.first { $0.url == "https://example.com/wait-b.bin" }
        let c = vm.downloads.first { $0.url == "https://example.com/wait-c.bin" }
        #expect(a?.status == .active)
        #expect(b?.status == .active)
        #expect(c?.status == .waiting)
        #expect(engine.started.count == 2)
    }

    @Test func addDownloadFirstStartsEvenWhenLimitIsOne() {
        let engine = FakeEngine()
        let vm = makeVM(engine: engine, maxConcurrentDownloads: 1)
        vm.addDownload(url: "https://example.com/limit-one-a.bin")
        vm.addDownload(url: "https://example.com/limit-one-b.bin")
        let a = vm.downloads.first { $0.url == "https://example.com/limit-one-a.bin" }
        let b = vm.downloads.first { $0.url == "https://example.com/limit-one-b.bin" }
        #expect(a?.status == .active)
        #expect(b?.status == .waiting)
        #expect(engine.started == [a?.id].compactMap { $0 })
    }

    @Test func pauseDownloadPausesEngine() {
        let engine = FakeEngine()
        let vm = makeVM(engine: engine)
        let d = Download(filename: "pause.bin", url: "https://example.com/pause.bin", status: .active)
        vm.downloads = [d]
        vm.pauseDownload(id: d.id)
        let result = vm.downloads.first { $0.id == d.id }
        #expect(result?.status == .paused)
        #expect(engine.paused.contains(d.id))
    }

    @Test func resumeDownloadFallsBackToStartWhenEngineCantResume() {
        let engine = FakeEngine()
        engine.resumeResult = false
        let vm = makeVM(engine: engine)
        let d = Download(filename: "resume-fallback.bin", url: "https://example.com/resume-fallback.bin", status: .paused)
        vm.downloads = [d]
        vm.resumeDownload(id: d.id)
        let result = vm.downloads.first { $0.id == d.id }
        #expect(result?.status == .active)
        #expect(engine.resumed.contains(d.id))
        #expect(engine.started.contains(d.id))
    }

    @Test func resumeDownloadUsesEngineResumeWhenAvailable() {
        let engine = FakeEngine()
        engine.resumeResult = true
        let vm = makeVM(engine: engine)
        let d = Download(filename: "resume-ok.bin", url: "https://example.com/resume-ok.bin", status: .paused)
        vm.downloads = [d]
        vm.resumeDownload(id: d.id)
        #expect(engine.resumed.contains(d.id))
        #expect(engine.started.isEmpty)
    }

    @Test func setPriorityPausesOthersAndRestoresOnCancel() {
        let engine = FakeEngine()
        let vm = makeVM(engine: engine)
        let a = Download(filename: "pri-a.bin", url: "https://example.com/pri-a.bin", status: .active)
        let b = Download(filename: "pri-b.bin", url: "https://example.com/pri-b.bin", status: .active)
        let c = Download(filename: "pri-c.bin", url: "https://example.com/pri-c.bin", status: .active)
        vm.downloads = [a, b, c]

        vm.setPriorityDownload(id: a.id)
        let afterSet = vm.downloads
        #expect(afterSet.first { $0.id == a.id }?.status == .active)
        #expect(afterSet.first { $0.id == a.id }?.isPriorityDownload == true)
        #expect(afterSet.first { $0.id == b.id }?.status == .paused)
        #expect(afterSet.first { $0.id == c.id }?.status == .paused)
        #expect(engine.paused.contains(b.id))
        #expect(engine.paused.contains(c.id))

        vm.cancelPriorityDownload(id: a.id)
        let afterCancel = vm.downloads
        #expect(afterCancel.first { $0.id == a.id }?.isPriorityDownload == false)
        #expect(afterCancel.first { $0.id == b.id }?.status == .active)
        #expect(afterCancel.first { $0.id == c.id }?.status == .active)
        #expect(engine.resumed.contains(b.id))
        #expect(engine.resumed.contains(c.id))
    }

    @Test func deleteDownloadCancelsActiveEngineTask() {
        let engine = FakeEngine()
        let vm = makeVM(engine: engine)
        let tempDir = NSTemporaryDirectory() + "/delete-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tempDir) }
        let d = Download(filename: "delete.bin", url: "https://example.com/delete.bin", status: .active, savePath: tempDir)
        vm.downloads = [d]
        vm.deleteDownload(id: d.id)
        #expect(vm.downloads.allSatisfy { $0.id != d.id })
        #expect(engine.cancelled.contains(d.id))
    }

    @Test func downloadLimitForwardsToEngine() {
        let engine = FakeEngine()
        let vm = makeVM(engine: engine)
        let d = Download(filename: "limit.bin", url: "https://example.com/limit.bin", status: .active)
        vm.downloads = [d]
        vm.setDownloadLimit(id: d.id, limit: 512)
        #expect(engine.speedLimits[d.id] == 512)
        #expect(vm.downloads.first { $0.id == d.id }?.downloadLimit == 512)
    }

    @Test func maxChunksForwardsToEngine() {
        let engine = FakeEngine()
        let vm = makeVM(engine: engine)
        let d = Download(filename: "chunks.bin", url: "https://example.com/chunks.bin", status: .active)
        vm.downloads = [d]
        vm.setMaxChunks(id: d.id, count: 4)
        #expect(engine.maxConcurrents[d.id] == 4)
        #expect(vm.downloads.first { $0.id == d.id }?.maxConcurrentChunks == 4)
    }

    @Test func resumeSendsStartedNotification() {
        let engine = FakeEngine()
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore(), notifier: notifier)
        let d = Download(filename: "notif.bin", url: "https://example.com/notif.bin", status: .paused)
        vm.downloads = [d]
        vm.resumeDownload(id: d.id)
        #expect(requests.count == 1)
        #expect(requests[0].identifier == d.id.uuidString + "-started")
        #expect(requests[0].content.body == "notif.bin")
    }

    @Test func completionSendsCompletedNotification() {
        let engine = FakeEngine()
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore(), notifier: notifier)
        let d = Download(filename: "done.bin", url: "https://example.com/done.bin", status: .paused)
        vm.downloads = [d]
        vm.resumeDownload(id: d.id)
        engine.fireCompletion(id: d.id, result: .success(()))
        drainMain()
        #expect(requests.contains { $0.identifier == d.id.uuidString + "-completed" && $0.content.body == AppConfig.defaultDownloadDir + "/done.bin" })
    }

    @Test func failureSendsFailedNotification() {
        let engine = FakeEngine()
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore(), notifier: notifier)
        let d = Download(filename: "fail.bin", url: "https://example.com/fail.bin", status: .paused)
        vm.downloads = [d]
        vm.resumeDownload(id: d.id)
        engine.fireCompletion(id: d.id, result: .failure(DownloadError.network(URLError(.notConnectedToInternet))))
        drainMain()
        #expect(requests.contains { $0.identifier == d.id.uuidString + "-failed" && $0.content.body.hasPrefix("fail.bin — ") })
    }

    private func drainMain() {
        // Let the queued main-async completion handler run before asserting.
        DispatchQueue.main.sync { }
    }
}
