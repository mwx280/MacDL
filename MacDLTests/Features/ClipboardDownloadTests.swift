import Testing
import Foundation
import UserNotifications
import MacDLCore
@testable import MacDL

@MainActor @Suite struct ClipboardDownloadTests {
    @Test func extractsValidURLs() {
        let links = ContentViewModel.downloadLinks(from: "https://e.com/a.zip http://f.org/b.txt")
        #expect(links == ["https://e.com/a.zip", "http://f.org/b.txt"])
    }

    @Test func ignoresPlainText() {
        let links = ContentViewModel.downloadLinks(from: "hello world, this is not a link")
        #expect(links.isEmpty)
    }

    @Test func ignoresInvalidSchemes() {
        let links = ContentViewModel.downloadLinks(from: "ftp://e.com/a.zip file:///tmp/x")
        #expect(links.isEmpty)
    }

    @Test func handlesNewlines() {
        let links = ContentViewModel.downloadLinks(from: "line1\nhttps://e.com/one.zip\nline3")
        #expect(links == ["https://e.com/one.zip"])
    }

    @Test func trimsTrailingPunctuation() {
        let links = ContentViewModel.downloadLinks(from: "See https://e.com/a.zip, then https://f.org/b.zip;")
        #expect(links == ["https://e.com/a.zip", "https://f.org/b.zip"])
    }

    @Test func handleLinksStartsDownloads() {
        let engine = FakeEngine()
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore())
        vm.handleDownloadLinks("https://example.com/clip-a.bin https://example.com/clip-b.bin")
        #expect(vm.downloads.count == 2)
        #expect(engine.started.count == 2)
    }

    @Test func handleLinksWithDuplicateAsksRedownload() {
        let engine = FakeEngine()
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore(), notifier: notifier)
        let existing = Download(filename: "dup.bin", url: "https://example.com/dup.bin", status: .active)
        vm.downloads = [existing]
        vm.handleDownloadLinks("https://example.com/dup.bin https://example.com/new.bin")
        #expect(vm.downloads.contains { $0.url == "https://example.com/new.bin" })
        // The duplicate prompts a re-download notification instead of being added.
        #expect(requests.contains { $0.content.userInfo["url"] as? String == "https://example.com/dup.bin" })
    }

    @Test func allowDuplicateAddsExistingUrl() {
        let engine = FakeEngine()
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore())
        let existing = Download(filename: "dup.bin", url: "https://example.com/dup.bin", status: .active)
        vm.downloads = [existing]
        vm.addDownload(url: "https://example.com/dup.bin", allowDuplicate: true)
        #expect(vm.downloads.filter { $0.url == "https://example.com/dup.bin" }.count == 2)
    }

    @Test func redownloadNotificationTriggersAdd() {
        let engine = FakeEngine()
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore())
        // The .requestRedownload observer is only installed by the real app's
        // startAppServices(); install it here to exercise the app flow.
        vm.startAppServices()
        NotificationCenter.default.post(name: .requestRedownload, object: "https://example.com/redl.bin")
        // The test already runs on the main thread; pump it so the main-queue
        // observer runs before asserting.
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        #expect(vm.downloads.contains { $0.url == "https://example.com/redl.bin" })
        vm.stopAppServices()
    }

    @Test func handleLinksWithoutLinksNotifies() {
        let engine = FakeEngine()
        var requests: [UNNotificationRequest] = []
        let notifier = DownloadNotifier(post: { requests.append($0) })
        notifier.authorized = true
        let vm = ContentViewModel(engine: engine, persistence: makePersistence(), settings: SettingsStore(), notifier: notifier)
        vm.handleDownloadLinks("this is just some text")
        #expect(requests.count == 1)
        #expect(requests[0].identifier.hasSuffix("-message"))
        #expect(vm.downloads.isEmpty)
    }

    private func makePersistence() -> DownloadPersistence {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip-tests-\(UUID().uuidString)", isDirectory: true)
        return DownloadPersistence(fileURL: dir.appendingPathComponent("downloads.json"))
    }
}
