import Testing
import Foundation
import UserNotifications
import MacDLCore
@testable import MacDL

// Inject FakeEngine to verify ContentViewModel's action logic against the engine, no real network needed.
@MainActor @Suite(.serialized) struct ContentViewModelEngineTests {
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

    @Test func addDownloadDefaultsToAutoConnections() {
        // Fresh settings default to Auto (0); a new download must carry the
        // sentinel through to the model so the engine adapts connections.
        let engine = FakeEngine()
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "auto-conn-\(UUID().uuidString)")!)
        settings.maxConnections = 0
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: settings)
        let url = "https://example.com/auto-conn.bin"
        vm.addDownload(url: url)
        #expect(vm.downloads.first { $0.url == url }?.maxConcurrentChunks == 0)
    }

    @Test func addDownloadWithExplicitConnectionsStoresThem() {
        let engine = FakeEngine()
        let vm = makeVM(engine: engine)
        let url = "https://example.com/fixed-conn.bin"
        vm.addDownload(url: url, connections: 4)
        #expect(vm.downloads.first { $0.url == url }?.maxConcurrentChunks == 4)
    }

    @Test func realEngineAddDownloadIsNoopUnderTestHost() {
        // Regression: under the XCTest host the app's real ContentViewModel also
        // observes global paste/redownload notifications. addDownload must be a
        // no-op for the real engine during tests, or it would spawn real
        // downloads (e.g. redl.bin.macdl) into ~/Downloads.
        let vm = ContentViewModel()
        let before = vm.downloads.count
        vm.addDownload(url: "https://example.com/noop.bin")
        #expect(vm.downloads.count == before)
        #expect(!vm.downloads.contains { $0.url == "https://example.com/noop.bin" })
    }

    @Test func redownloadConfirmedRestartsCompletedDownload() {
        let engine = FakeEngine()
        let vm = makeVM(engine: engine)
        let d = Download(filename: "redo.bin", url: "https://example.com/redo.bin", status: .completed)
        vm.downloads = [d]
        vm.redownloadConfirmation = { _, _ in true }
        vm.redownloadDownload(id: d.id)
        let result = vm.downloads.first { $0.id == d.id }
        #expect(result?.status == .active)
        #expect(result?.totalSize == 0)
        #expect(result?.chunks.isEmpty == true)
        #expect(engine.started.contains(d.id))
    }

    @Test func redownloadDeclinedKeepsCompleted() {
        let engine = FakeEngine()
        let vm = makeVM(engine: engine)
        let d = Download(filename: "redo-no.bin", url: "https://example.com/redo-no.bin", status: .completed)
        vm.downloads = [d]
        vm.redownloadConfirmation = { _, _ in false }
        vm.redownloadDownload(id: d.id)
        #expect(vm.downloads.first { $0.id == d.id }?.status == .completed)
        #expect(engine.started.isEmpty)
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

    @Test func resumeNonResumableResetsProgress() {
        let engine = FakeEngine()
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore())
        let d = Download(filename: "nr.bin", url: "https://example.com/nr.bin", totalSize: 1000, downloadedSize: 500, status: .paused, supportsResume: false)
        vm.downloads = [d]
        vm.resumeDownload(id: d.id)
        let resumed = vm.downloads.first { $0.id == d.id }
        #expect(resumed?.status == .active)
        #expect(resumed?.downloadedSize == 0)
        #expect(resumed?.totalSize == 0)
        #expect(resumed?.chunks.isEmpty == true)
    }

    @Test func resumeResumableKeepsProgress() {
        let engine = FakeEngine()
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore())
        let d = Download(filename: "r.bin", url: "https://example.com/r.bin", totalSize: 1000, downloadedSize: 500, status: .paused, supportsResume: true)
        vm.downloads = [d]
        vm.resumeDownload(id: d.id)
        let resumed = vm.downloads.first { $0.id == d.id }
        #expect(resumed?.downloadedSize == 500)
        #expect(resumed?.totalSize == 1000)
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

    @Test func completionSendsCompletedNotification() async {
        let engine = FakeEngine()
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore(), notifier: notifier)
        let d = Download(filename: "done.bin", url: "https://example.com/done.bin", status: .paused)
        vm.downloads = [d]
        vm.resumeDownload(id: d.id)
        engine.fireCompletion(id: d.id, result: .success(()))
        await drainMain()
        #expect(requests.contains { $0.identifier == d.id.uuidString + "-completed" && $0.content.body == AppConfig.defaultDownloadDir + "/done.bin" })
    }

    @Test func failureSendsFailedNotification() async {
        let engine = FakeEngine()
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore(), notifier: notifier)
        let d = Download(filename: "fail.bin", url: "https://example.com/fail.bin", status: .paused)
        vm.downloads = [d]
        vm.resumeDownload(id: d.id)
        engine.fireCompletion(id: d.id, result: .failure(DownloadError.network(URLError(.notConnectedToInternet))))
        await drainMain()
        #expect(requests.contains { $0.identifier == d.id.uuidString + "-failed" && $0.content.body.hasPrefix("fail.bin — ") })
    }

    @Test func priorityFailurePostsDedicatedNotification() async {
        let engine = FakeEngine()
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore(), notifier: notifier)
        let a = Download(filename: "pri.bin", url: "https://example.com/pri.bin", status: .paused)
        let b = Download(filename: "other.bin", url: "https://example.com/other.bin", status: .active)
        vm.downloads = [a, b]
        vm.resumeDownload(id: a.id)
        vm.setPriorityDownload(id: a.id)
        engine.fireCompletion(id: a.id, result: .failure(DownloadError.network(URLError(.notConnectedToInternet))))
        await drainMain()
        // A dedicated "message" notification replaces the generic "-failed" one.
        #expect(requests.contains { $0.identifier.hasSuffix("-message") && $0.content.body.contains("pri.bin") })
        #expect(!requests.contains { $0.identifier == a.id.uuidString + "-failed" })
    }

    @Test func retryingHandlerUpdatesDownloadState() async {
        // The engine's "stalled, retrying" signal must land on the model so the
        // UI can show it; it is transient and starts false.
        let engine = FakeEngine()
        let vm = makeVM(engine: engine)
        let url = "https://example.com/retry.bin"
        vm.addDownload(url: url)
        guard let id = vm.downloads.first(where: { $0.url == url })?.id else {
            Issue.record("download not created")
            return
        }
        #expect(vm.downloads.first { $0.id == id }?.isRetrying == false)
        engine.fireRetrying(id: id, retrying: true)
        await drainMain()
        #expect(vm.downloads.first { $0.id == id }?.isRetrying == true)
        engine.fireRetrying(id: id, retrying: false)
        await drainMain()
        #expect(vm.downloads.first { $0.id == id }?.isRetrying == false)
    }

    private func drainMain() async {
        // Let the queued main-actor completion task run before asserting.
        for _ in 0..<8 { await Task.yield() }
    }

    // Polls until the condition holds or the timeout passes. Timing-sensitive
    // assertions like this are unreliable with fixed sleeps in a Swift 6 test
    // host, where detached tasks can be delayed.
    private func waitForCondition(timeout: Duration = .milliseconds(2000), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func completionMovesStagingToFinal() async throws {
        let engine = FakeEngine()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dl-rename-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        // Mock the notifier: sending a real completion notification from a
        // test host can block on UNUserNotificationCenter and stall the suite.
        let notifier = DownloadNotifier(post: { _ in }, removePending: { _ in }, settings: SettingsStore())
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore(), notifier: notifier)
        let bookmark = try? URL(fileURLWithPath: tempDir.path).bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let d = Download(filename: "done.bin", url: "https://example.com/done.bin", totalSize: 100, downloadedSize: 100, status: .paused, savePath: tempDir.path, saveBookmark: bookmark, supportsResume: true)
        try Data("hello".utf8).write(to: tempDir.appendingPathComponent("done.bin.macdl"))
        vm.downloads = [d]
        vm.resumeDownload(id: d.id)
        engine.fireCompletion(id: d.id, result: .success(()))
        await waitForCondition { vm.downloads.first(where: { $0.id == d.id })?.status == .completed }
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("done.bin").path))
        #expect(!FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("done.bin.macdl").path))
        #expect(vm.downloads.first(where: { $0.id == d.id })?.status == .completed)
    }

    @Test func missingStagingFileMarksError() async throws {
        let engine = FakeEngine()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dl-missing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore())
        let d = Download(filename: "gone.bin", url: "https://example.com/gone.bin", totalSize: 1000, downloadedSize: 500, status: .active, savePath: tempDir.path)
        vm.downloads = [d]
        vm.service.checkFilesAndPersistIfNeeded()
        // Wait for the detached file probe to hop back to the main actor.
        await waitForCondition { vm.downloads.first { $0.id == d.id }?.status == .error }
        let updated = vm.downloads.first { $0.id == d.id }
        #expect(updated?.status == .error)
        #expect(updated?.errorKey == "Download file has been deleted")
    }

    @Test func missingStagingFilePostsFailedNotification() async throws {
        let engine = FakeEngine()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dl-missing-notif-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore(), notifier: notifier)
        let d = Download(filename: "gone.bin", url: "https://example.com/gone.bin", totalSize: 1000, downloadedSize: 500, status: .active, savePath: tempDir.path)
        vm.downloads = [d]
        vm.service.checkFilesAndPersistIfNeeded()
        await waitForCondition { vm.downloads.first { $0.id == d.id }?.status == .error }
        #expect(requests.contains { $0.identifier == d.id.uuidString + "-failed" && $0.content.body.hasPrefix("gone.bin — ") })
    }

    @Test func missingStagingFileStartsWaitingDownload() async throws {
        let engine = FakeEngine()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dl-missing-waiting-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let suite = "missing-waiting-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let settings = SettingsStore(defaults: defaults)
        settings.maxConcurrentDownloads = 1
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: settings)
        let active = Download(filename: "gone.bin", url: "https://example.com/gone.bin", totalSize: 1000, downloadedSize: 500, status: .active, savePath: tempDir.path)
        let waiting = Download(filename: "wait.bin", url: "https://example.com/wait.bin", status: .waiting)
        vm.downloads = [active, waiting]
        // Simulate the app having registered the waiting download with the
        // engine's scheduler (as happens on add or at launch).
        engine.enqueue(id: waiting.id, url: URL(string: waiting.url)!,
                       destinationURL: URL(fileURLWithPath: tempDir.path + "/wait.bin.macdl"),
                       speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
        vm.service.checkFilesAndPersistIfNeeded()
        await waitForCondition { vm.downloads.first { $0.id == active.id }?.status == .error }
        await drainMain()
        #expect(vm.downloads.first { $0.id == waiting.id }?.status == .active)
        #expect(engine.started.contains(waiting.id))
    }

    @Test func clearSelectedDeletesFiles() throws {
        let engine = FakeEngine()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dl-bulk-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore())
        let a = Download(filename: "a.bin", url: "https://example.com/a.bin", status: .completed, savePath: tempDir.path)
        let b = Download(filename: "b.bin", url: "https://example.com/b.bin", status: .completed, savePath: tempDir.path)
        try Data("a".utf8).write(to: tempDir.appendingPathComponent("a.bin"))
        try Data("b".utf8).write(to: tempDir.appendingPathComponent("b.bin"))
        vm.downloads = [a, b]
        vm.service.clearSelected(ids: [a.id, b.id], deleteFiles: true)
        #expect(vm.downloads.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("a.bin").path))
        #expect(!FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("b.bin").path))
    }

    @Test func clearSelectedWithoutFilesKeepsFiles() throws {
        let engine = FakeEngine()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("dl-bulk2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore())
        let a = Download(filename: "a.bin", url: "https://example.com/a.bin", status: .completed, savePath: tempDir.path)
        try Data("a".utf8).write(to: tempDir.appendingPathComponent("a.bin"))
        vm.downloads = [a]
        vm.service.clearSelected(ids: [a.id], deleteFiles: false)
        #expect(vm.downloads.isEmpty)
        #expect(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("a.bin").path))
    }

    @Test func metalinkFetchFailureMarksError() async {
        // A Metalink that cannot be fetched/parsed must surface an error entry,
        // never a download of the .metalink document itself.
        DownloadService.fetchMetalinkOverride = { _ in nil }
        defer { DownloadService.fetchMetalinkOverride = nil }
        let engine = FakeEngine()
        let vm = makeVM(engine: engine)
        let url = "https://example.com/broken.metalink"
        vm.addDownload(url: url)
        await waitForCondition { vm.downloads.contains { $0.url == url } }
        let d = vm.downloads.first { $0.url == url }
        #expect(d?.status == .error)
        #expect(d?.errorKey == "Invalid metalink")
        #expect(engine.started.isEmpty)
    }

}
