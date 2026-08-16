import Testing
import Foundation
import MacDLCore
@testable import MacDL

@MainActor @Suite(.serialized) struct PriorityCoordinatorTests {
    private func makePersistence() -> DownloadPersistence {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("prio-tests-\(UUID().uuidString)", isDirectory: true)
        return DownloadPersistence(fileURL: dir.appendingPathComponent("downloads.json"))
    }

    private func makeCoordinator() -> (PriorityDownloadCoordinator, DownloadStore, FakeEngine) {
        let engine = FakeEngine()
        let store = DownloadStore(persistence: makePersistence())
        let notifier = DownloadNotifier(post: { _ in })
        let engineCoord = DownloadEngineCoordinator(engine: engine, store: store, notifier: notifier, settings: SettingsStore())
        var resumed: [UUID] = []
        let priority = PriorityDownloadCoordinator(store: store, engine: engineCoord) { id in
            resumed.append(id)
            // Mimic ContentViewModel.resumeDownload: mark the download active.
            if let i = store.index(of: id) { store.downloads[i].status = .active }
        }
        return (priority, store, engine)
    }

    /// Registers a download with the fake engine's scheduler (as the app does
    /// when the download actually starts), so it counts as running.
    private func startDownload(_ engine: FakeEngine, _ d: Download) {
        _ = engine.schedule(id: d.id, url: URL(string: d.url)!,
                            destinationURL: URL(fileURLWithPath: "/tmp/prio-" + d.filename),
                            speedLimit: 0, chunkSize: 262144, maxConcurrent: 4, chunks: [], mirrors: [])
    }

    private func drainMain() async {
        for _ in 0..<8 { await Task.yield() }
    }

    @Test func setPriorityPausesOthersAndRestoresOnCancel() async {
        let (priority, store, engine) = makeCoordinator()
        let a = Download(filename: "a.bin", url: "https://e.com/a.bin", status: .active)
        let b = Download(filename: "b.bin", url: "https://e.com/b.bin", status: .active)
        let c = Download(filename: "c.bin", url: "https://e.com/c.bin", status: .active)
        store.downloads = [a, b, c]
        for d in [a, b, c] { startDownload(engine, d) }

        priority.setPriority(id: a.id)
        await drainMain()
        #expect(store.downloads.first { $0.id == a.id }?.status == .active)
        #expect(store.downloads.first { $0.id == a.id }?.isPriorityDownload == true)
        #expect(store.downloads.first { $0.id == b.id }?.status == .paused)
        #expect(store.downloads.first { $0.id == b.id }?.pausedForPriority == true)
        #expect(store.downloads.first { $0.id == c.id }?.pausedForPriority == true)
        #expect(engine.paused.contains(b.id))
        #expect(engine.paused.contains(c.id))

        priority.cancelPriority(id: a.id)
        await drainMain()
        #expect(store.downloads.first { $0.id == a.id }?.isPriorityDownload == false)
        #expect(store.downloads.first { $0.id == b.id }?.status == .active)
        #expect(store.downloads.first { $0.id == b.id }?.pausedForPriority == false)
    }

    @Test func setPriorityReplacesPrevious() async {
        let (priority, store, engine) = makeCoordinator()
        let a = Download(filename: "a.bin", url: "https://e.com/a.bin", status: .active)
        let b = Download(filename: "b.bin", url: "https://e.com/b.bin", status: .active)
        store.downloads = [a, b]
        for d in [a, b] { startDownload(engine, d) }

        priority.setPriority(id: a.id)
        await drainMain()
        priority.setPriority(id: b.id)
        await drainMain()
        #expect(store.downloads.first { $0.id == a.id }?.isPriorityDownload == false)
        #expect(store.downloads.first { $0.id == a.id }?.status == .paused)
        #expect(store.downloads.first { $0.id == b.id }?.isPriorityDownload == true)
        #expect(store.downloads.first { $0.id == b.id }?.status == .active)
        #expect(engine.paused.contains(a.id))
    }

    @Test func endExcludingSkipsDeletedDownload() async {
        let (priority, store, engine) = makeCoordinator()
        let a = Download(filename: "a.bin", url: "https://e.com/a.bin", status: .active)
        let b = Download(filename: "b.bin", url: "https://e.com/b.bin", status: .active)
        store.downloads = [a, b]
        for d in [a, b] { startDownload(engine, d) }

        priority.setPriority(id: a.id)
        await drainMain()
        priority.end(excluding: a.id)
        await drainMain()
        #expect(store.downloads.first { $0.id == a.id }?.isPriorityDownload == false)
        #expect(store.downloads.first { $0.id == b.id }?.status == .active)
        #expect(store.downloads.first { $0.id == b.id }?.pausedForPriority == false)
        // a was skipped (deleted), so it must not be resumed.
        #expect(engine.paused.contains(b.id))
    }

    @Test func restoreFromStoreRebuildsState() {
        let (priority, store, _) = makeCoordinator()
        let a = Download(filename: "a.bin", url: "https://e.com/a.bin", status: .active, isPriorityDownload: true)
        let b = Download(filename: "b.bin", url: "https://e.com/b.bin", status: .paused, pausedForPriority: true)
        store.downloads = [a, b]

        priority.restoreFromStore()
        #expect(priority.priorityDownloadID == a.id)
        #expect(priority.pausedForPriority == [b.id])
    }

    @Test func endPriorityRestoresRegisteredPaused() async {
        // After a restart the engine forgets which downloads were paused for
        // priority; restoreFromStore re-registers them so end restores them.
        let (priority, store, engine) = makeCoordinator()
        let a = Download(filename: "a.bin", url: "https://e.com/a.bin", status: .active, isPriorityDownload: true)
        let b = Download(filename: "b.bin", url: "https://e.com/b.bin", status: .paused, pausedForPriority: true)
        store.downloads = [a, b]

        priority.restoreFromStore()
        priority.cancelPriority(id: a.id)
        await drainMain()
        #expect(store.downloads.first { $0.id == b.id }?.status == .active)
        #expect(store.downloads.first { $0.id == b.id }?.pausedForPriority == false)
        #expect(engine.priorityResumedIds.contains(b.id))
    }
}
