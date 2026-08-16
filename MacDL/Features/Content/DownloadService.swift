import Foundation
import AppKit
import Observation
import MacDLCore

// Owns the download lifecycle: adding/starting, pause/resume, retry/redownload,
// delete, priority, engine-completion handling and file-integrity checks.
// ContentViewModel keeps the view state (selection, filters) and forwards
// lifecycle calls here, so the business logic is testable in isolation.
@MainActor
@Observable
final class DownloadService {
    let store: DownloadStore
    let coordinator: DownloadEngineCoordinator
    private(set) var priority: PriorityDownloadCoordinator!

    private let engine: DownloadEngineProtocol
    private let notifier: DownloadNotifier
    private let settings: SettingsStore
    private let persistence: DownloadPersistence

    /// Downloads currently in the range-probe/detection phase (transient, not persisted).
    var probingDownloads = Set<UUID>()

    var downloads: [Download] {
        get { store.downloads }
        set { store.downloads = newValue }
    }

    init(engine: DownloadEngineProtocol = DownloadEngine.shared,
         persistence: DownloadPersistence = .shared,
         settings: SettingsStore = .shared,
         notifier: DownloadNotifier = .shared) {
        self.engine = engine
        self.persistence = persistence
        self.settings = settings
        self.notifier = notifier
        let store = DownloadStore(persistence: persistence)
        self.store = store
        let coordinator = DownloadEngineCoordinator(engine: engine, store: store, notifier: notifier, settings: settings)
        self.coordinator = coordinator
        let priority = PriorityDownloadCoordinator(store: store, engine: coordinator) { [weak self] id in
            self?.resumeDownload(id: id)
        }
        self.priority = priority
        coordinator.progress.setCancelHandler { [weak self] id in self?.cancelProgressDownload(id) }
        coordinator.onTaskCompletion = { [weak self] id, result in
            self?.handleEngineCompletion(id: id, result: result)
        }
        coordinator.onPhaseChange = { [weak self] id, isProbing in
            guard let self else { return }
            if isProbing { self.probingDownloads.insert(id) } else { self.probingDownloads.remove(id) }
        }
        // A fresh app launch must not keep tasks from a previous session running.
        let wasActive = store.downloads.filter { $0.status == .active }.map(\.id)
        for i in store.downloads.indices where store.downloads[i].status == .active {
            store.downloads[i].status = .paused
        }
        priority.restoreFromStore()
        // When enabled, pick up exactly the tasks that were still downloading at
        // quit time; manually paused ones stay paused.
        if settings.autoResumeOnLaunch {
            for id in wasActive { resumeDownload(id: id) }
        }
    }

    // MARK: - Clipboard / Links

    /// Pulls http/https URLs out of arbitrary text (whitespace / newline separated).
    static func downloadLinks(from text: String) -> [String] {
        let trailing = CharacterSet(charactersIn: ",.;:!?)]}\"")
        return text.split(whereSeparator: { $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: trailing) }
            .filter { token in
                guard let url = URL(string: token),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https",
                      url.host != nil
                else { return false }
                return true
            }
    }

    func downloadFromClipboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        handleDownloadLinks(text)
    }

    func handleDownloadLinks(_ text: String) {
        let links = Self.downloadLinks(from: text)
        guard !links.isEmpty else {
            notifier.notify(title: LanguageManager.shared.localized("No Download Link"),
                            body: LanguageManager.shared.localized("The clipboard doesn't contain a valid download link."))
            return
        }
        for link in links {
            if downloads.contains(where: { $0.url == link }) {
                notifier.notifyRedownload(link)
            } else {
                addDownload(url: link)
            }
        }
    }

    // MARK: - Download Actions

    func addDownload(url: String, savePath: String? = nil, saveBookmark: Data? = nil, dlLimit: Int = 0, connections: Int? = nil, allowDuplicate: Bool = false) {
        // Under the XCTest host the app's real ContentViewModel also observes the
        // global paste/redownload notifications. Never let it touch the real engine
        // or disk during tests, or it would spawn real downloads into ~/Downloads.
        if ProcessInfo.isRunningTests,
           (engine as AnyObject) === DownloadEngine.shared {
            return
        }
        guard let sourceURL = URL(string: url) else {
            addResolvedDownload(primary: nil, url: url, mirrors: [], checksum: nil, filename: nil,
                                savePath: savePath, saveBookmark: saveBookmark, dlLimit: dlLimit,
                                connections: connections, allowDuplicate: allowDuplicate)
            return
        }
        // A Metalink document lists mirrors + a checksum: fetch and parse it first,
        // then start the download from those sources (no manual mirror hunting).
        if MetalinkParser.isMetalinkURL(sourceURL) {
            Task { [weak self] in
                let metalink = await Self.fetchMetalink(sourceURL)
                await MainActor.run {
                    guard let self else { return }
                    if let metalink, let primary = metalink.urls.first {
                        self.addResolvedDownload(
                            primary: primary,
                            url: url,
                            mirrors: Array(metalink.urls.dropFirst()),
                            checksum: metalink.checksum,
                            filename: metalink.filename,
                            savePath: savePath, saveBookmark: saveBookmark, dlLimit: dlLimit,
                            connections: connections, allowDuplicate: allowDuplicate)
                    } else {
                        // A failed or unparsable Metalink must surface an error,
                        // not silently download the .metalink document itself.
                        self.addInvalidMetalinkDownload(url: url, savePath: savePath,
                                                        saveBookmark: saveBookmark,
                                                        dlLimit: dlLimit, connections: connections)
                    }
                }
            }
            return
        }
        addResolvedDownload(primary: sourceURL, url: url, mirrors: [], checksum: nil,
                            filename: sourceURL.lastPathComponent,
                            savePath: savePath, saveBookmark: saveBookmark, dlLimit: dlLimit,
                            connections: connections, allowDuplicate: allowDuplicate)
    }

    /// Creates and starts a download from a resolved primary URL (plus optional
    /// mirrors and checksum). `primary == nil` marks an invalid/unparseable URL.
    private func addResolvedDownload(primary: URL?, url: String, mirrors: [URL], checksum: String?,
                                     filename: String?, savePath: String?, saveBookmark: Data?,
                                     dlLimit: Int, connections: Int?, allowDuplicate: Bool) {
        let name = filename ?? primary?.lastPathComponent
            ?? URL(string: url)?.lastPathComponent ?? "download-\(downloads.count + 1)"
        let dir = savePath ?? AppConfig.defaultDownloadDir
        let resolvedURL = primary?.absoluteString ?? url

        if !allowDuplicate, let existing = downloads.first(where: { $0.url == resolvedURL || ($0.filename == name && ($0.savePath ?? AppConfig.defaultDownloadDir) == dir) }) {
            switch DuplicatePolicy.decide(for: existing) {
            case .proceed:
                break
            case .resume:
                resumeDownload(id: existing.id)
                return
            case .skip:
                return
            }
        }

        let d = Download(
            filename: name,
            url: resolvedURL,
            status: .active,
            savePath: savePath,
            saveBookmark: saveBookmark,
            downloadLimit: dlLimit > 0 ? dlLimit : nil,
            maxConcurrentChunks: connections ?? settings.maxConnections,
            expectedChecksum: checksum,
            mirrors: mirrors.map(\.absoluteString)
        )
        store.append(d)
        store.save()

        guard let sourceURL = primary ?? URL(string: url) else {
            store.update(d.id) {
                $0.status = .error
                $0.errorKey = "Invalid URL"
                $0.errorMessage = LanguageManager.shared.localized("Invalid URL")
            }
            store.save()
            return
        }

        // Count actives excluding the one we just added; otherwise the new download
        // always nudges the count one over the limit and never starts at limit 1.
        let activeCount = downloads.filter { $0.status == .active && $0.id != d.id }.count
        if activeCount >= max(settings.maxConcurrentDownloads, 1) {
            store.update(d.id) { $0.status = .waiting }
            store.save()
            return
        }

        setupEngineTask(for: d.id, url: sourceURL, dlLimit: dlLimit)
    }

    /// Fetches and parses a Metalink document off the main thread.
    /// Test hook: `fetchMetalinkOverride` lets tests avoid a real network fetch.
    nonisolated(unsafe) static var fetchMetalinkOverride: ((URL) async -> MetalinkFile?)?

    private static func fetchMetalink(_ url: URL) async -> MetalinkFile? {
        if let override = fetchMetalinkOverride { return await override(url) }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return MetalinkParser.parse(data)
        } catch {
            return nil
        }
    }

    /// Records a failed Metalink add as an error entry so the user sees what
    /// went wrong instead of a .metalink file landing in the download list.
    private func addInvalidMetalinkDownload(url: String, savePath: String?, saveBookmark: Data?,
                                            dlLimit: Int, connections: Int?) {
        let name = URL(string: url)?.lastPathComponent ?? "download-\(downloads.count + 1)"
        let d = Download(
            filename: name,
            url: url,
            status: .error,
            savePath: savePath,
            saveBookmark: saveBookmark,
            downloadLimit: dlLimit > 0 ? dlLimit : nil,
            errorMessage: LanguageManager.shared.localized("Invalid metalink"),
            errorKey: "Invalid metalink",
            maxConcurrentChunks: connections ?? settings.maxConnections
        )
        store.append(d)
        store.save()
    }

    private func startNextWaitingDownload() {
        let limit = max(settings.maxConcurrentDownloads, 1)
        while downloads.filter({ $0.status == .active }).count < limit,
              let idx = downloads.firstIndex(where: { $0.status == .waiting }) {
            downloads[idx].status = .active
            store.save()
            guard let sourceURL = URL(string: downloads[idx].url) else {
                downloads[idx].status = .error
                downloads[idx].errorKey = "Invalid URL"
                downloads[idx].errorMessage = LanguageManager.shared.localized("Invalid URL")
                store.save()
                continue
            }
            setupEngineTask(for: downloads[idx].id, url: sourceURL, dlLimit: downloads[idx].downloadLimit ?? 0)
        }
    }

    private func setupEngineTask(for id: UUID, url sourceURL: URL, dlLimit: Int) {
        guard let src = downloads.first(where: { $0.id == id }) else { return }
        if !coordinator.beginAccess(for: src) {
            store.update(id) {
                $0.status = .error
                $0.errorKey = "Download folder access lost. Choose it again in Settings."
                $0.errorMessage = LanguageManager.shared.localized("Download folder access lost. Choose it again in Settings.")
            }
            store.save()
            return
        }
        let dest = DownloadPath.staging(for: src)
        let speedLimit = Int64(dlLimit > 0 ? dlLimit : (src.downloadLimit ?? 0))
        coordinator.start(id: id, url: sourceURL, dest: dest, speedLimit: speedLimit,
                          chunkSize: src.chunkSize,
                          maxConcurrent: src.maxConcurrentChunks,
                          chunks: src.chunks)
    }

    func pauseDownload(id: UUID) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }), downloads[idx].status == .active else { return }
        if downloads[idx].supportsResume == false {
            guard DialogPresenter.confirmPauseNonResumable() else { return }
        }
        coordinator.pause(id)
        if coordinator.isTracked(id) {
            if !FileManager.default.fileExists(atPath: DownloadPath.staging(for: downloads[idx]).path) {
                downloads[idx].status = .error
                downloads[idx].errorKey = "Download file has been deleted"
                downloads[idx].errorMessage = LanguageManager.shared.localized("Download file has been deleted")
                store.save()
                return
            }
        }
        downloads[idx].status = .paused
        store.save()
    }

    func resumeDownload(id: UUID) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        guard downloads[idx].status == .paused || downloads[idx].status == .waiting else { return }

        if !coordinator.beginAccess(for: downloads[idx]) {
            downloads[idx].status = .error
            downloads[idx].errorKey = "Download folder access lost. Choose it again in Settings."
            downloads[idx].errorMessage = LanguageManager.shared.localized("Download folder access lost. Choose it again in Settings.")
            store.save()
            return
        }

        // A non-resumable (single-stream) download restarts from byte zero on
        // resume, so clear its progress or the bar sticks at the pre-pause value
        // while the engine rewrites the file.
        if downloads[idx].supportsResume == false {
            downloads[idx].downloadedSize = 0
            downloads[idx].totalSize = 0
            downloads[idx].chunks = []
        }

        downloads[idx].status = .active
        store.save()

        if coordinator.resume(id) { return }

        guard let sourceURL = URL(string: downloads[idx].url) else {
            downloads[idx].status = .error
            downloads[idx].errorKey = "Invalid URL"
            downloads[idx].errorMessage = LanguageManager.shared.localized("Invalid URL")
            store.save()
            return
        }

        let dest = DownloadPath.staging(for: downloads[idx])
        coordinator.start(id: id, url: sourceURL, dest: dest,
                          speedLimit: Int64(downloads[idx].downloadLimit ?? 0),
                          chunkSize: downloads[idx].chunkSize,
                          maxConcurrent: downloads[idx].maxConcurrentChunks,
                          chunks: downloads[idx].chunks)
    }

    func deleteDownload(id: UUID) {
        coordinator.progress.unpublish(for: id)
        coordinator.endAccess(for: id)
        if id == priority.priorityDownloadID {
            priority.end(excluding: id)
        }
        guard let d = downloads.first(where: { $0.id == id }) else { return }
        if d.status == .active {
            coordinator.cancel(id)
            coordinator.untrack(id)
        }
        coordinator.endAccess(for: id)
        let dir = d.savePath ?? AppConfig.defaultDownloadDir
        try? FileManager.default.removeItem(atPath: dir + "/" + d.filename + ".macdl")
        try? FileManager.default.removeItem(atPath: dir + "/" + d.filename)
        store.remove(id)
        store.save()
    }

    /// Re-downloads a finished download. Confirms first; if the destination file
    /// already exists the dialog warns that it will be overwritten.
    func redownloadDownload(id: UUID, confirmation: (Download, Bool) -> Bool) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        let d = downloads[idx]
        guard d.status == .completed else { return }

        let dir = d.savePath ?? AppConfig.defaultDownloadDir
        let finalPath = dir + "/" + d.filename
        let fileExists = FileManager.default.fileExists(atPath: finalPath)

        guard confirmation(d, fileExists) else { return }

        // Remove the finished file (and any stale staging) so the fresh download
        // starts clean instead of resuming old chunks.
        try? FileManager.default.removeItem(atPath: finalPath)
        try? FileManager.default.removeItem(atPath: dir + "/" + d.filename + ".macdl")

        downloads[idx].status = .active
        downloads[idx].errorMessage = nil
        downloads[idx].errorKey = nil
        downloads[idx].downloadedSize = 0
        downloads[idx].totalSize = 0
        downloads[idx].chunks = []
        downloads[idx].supportsResume = nil
        store.save()

        guard let sourceURL = URL(string: d.url) else {
            downloads[idx].status = .error
            downloads[idx].errorKey = "Invalid URL"
            downloads[idx].errorMessage = LanguageManager.shared.localized("Invalid URL")
            store.save()
            return
        }

        let activeCount = downloads.filter { $0.status == .active && $0.id != id }.count
        if activeCount >= max(settings.maxConcurrentDownloads, 1) {
            downloads[idx].status = .waiting
            store.save()
            return
        }

        setupEngineTask(for: id, url: sourceURL, dlLimit: d.downloadLimit ?? 0)
    }

    func retryDownload(id: UUID) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        let d = downloads[idx]
        if d.status == .active {
            coordinator.cancel(id)
            coordinator.untrack(id)
            coordinator.progress.unpublish(for: id)
        }
        coordinator.endAccess(for: id)
        let dir = d.savePath ?? AppConfig.defaultDownloadDir
        try? FileManager.default.removeItem(atPath: dir + "/" + d.filename + ".macdl")
        try? FileManager.default.removeItem(atPath: dir + "/" + d.filename)

        // Start clean: drop old chunks so a deleted or partial file isn't resumed
        // from stale offsets.
        downloads[idx].status = .active
        downloads[idx].errorMessage = nil
        downloads[idx].errorKey = nil
        downloads[idx].downloadedSize = 0
        downloads[idx].totalSize = 0
        downloads[idx].chunks = []
        store.save()

        guard let sourceURL = URL(string: d.url) else {
            downloads[idx].status = .error
            downloads[idx].errorKey = "Invalid URL"
            downloads[idx].errorMessage = LanguageManager.shared.localized("Invalid URL")
            return
        }

        setupEngineTask(for: id, url: sourceURL, dlLimit: d.downloadLimit ?? 0)
    }

    func setDownloadLimit(id: UUID, limit: Int) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[idx].downloadLimit = limit
        store.save()
        coordinator.setSpeedLimit(id: id, limit: limit)
    }

    func setMaxChunks(id: UUID, count: Int) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[idx].maxConcurrentChunks = count
        store.save()
        coordinator.setMaxConcurrent(id: id, count: count)
    }

    func pauseAllDownloads() {
        for i in downloads.indices where downloads[i].status == .active {
            coordinator.pause(downloads[i].id)
            downloads[i].status = .paused
        }
        store.save()
    }

    func resumeAllDownloads() {
        let ids = downloads.filter { $0.status == .paused || $0.status == .waiting }.map(\.id)
        for id in ids { resumeDownload(id: id) }
    }

    // MARK: - Priority download

    func setPriorityDownload(id: UUID) {
        priority.setPriority(id: id)
    }

    func cancelPriorityDownload(id: UUID) {
        priority.cancelPriority(id: id)
    }

    func clearSelected(ids: Set<UUID>, deleteFiles: Bool = false) {
        let toDelete = downloads.filter { ids.contains($0.id) }

        if let pid = priority.priorityDownloadID, toDelete.contains(where: { $0.id == pid }) {
            priority.end(excluding: pid)
        }

        for d in toDelete {
            coordinator.progress.unpublish(for: d.id)
            coordinator.endAccess(for: d.id)
            if d.status == .active {
                coordinator.cancel(d.id)
                coordinator.untrack(d.id)
            }
            let dir = d.savePath ?? AppConfig.defaultDownloadDir
            if deleteFiles {
                try? FileManager.default.removeItem(atPath: dir + "/" + d.filename + ".macdl")
                try? FileManager.default.removeItem(atPath: dir + "/" + d.filename)
            }
        }

        for id in toDelete.map(\.id) { store.remove(id) }
        store.save()
    }

    // MARK: - Engine completion

    private func cancelProgressDownload(_ id: UUID) {
        if let idx = store.index(of: id) {
            let d = store.downloads[idx]
            if d.status == .active {
                coordinator.pause(id)
            }
            store.downloads[idx].status = .paused
            store.save()
        }
    }

    private func recordError(id: UUID, key: String) {
        store.update(id) {
            $0.errorKey = key
            $0.errorMessage = LanguageManager.shared.localized(key)
        }
    }

    private func handleEngineCompletion(id: UUID, result: Result<Void, Error>) {
        probingDownloads.remove(id)
        guard let idx = store.index(of: id) else { return }
        switch result {
        case .success:
            coordinator.progress.unpublish(for: id)
            let staging = DownloadPath.staging(for: store.downloads[idx])
            let final = DownloadPath.destination(for: store.downloads[idx])
            if let expected = store.downloads[idx].expectedChecksum, !expected.isEmpty {
                // Verify off the main thread: SHA-256 over a large file would
                // otherwise stall the UI. Status stays non-completed until the
                // checksum passes, so the UI never flashes "done" then "error".
                let normalized = ChecksumVerifier.normalize(expected)
                Task.detached {
                    let actual = (try? ChecksumVerifier.sha256Hex(ofFile: staging)) ?? ""
                    await MainActor.run { [weak self] in
                        self?.finalizeVerifiedDownload(id: id, matches: actual == normalized && !actual.isEmpty, staging: staging, final: final)
                    }
                }
                return
            }
            store.downloads[idx].status = .completed
            try? FileManager.default.moveItem(at: staging, to: final)
            let dir = store.downloads[idx].savePath ?? AppConfig.defaultDownloadDir
            NSWorkspace.shared.noteFileSystemChanged(dir)
            notifier.notifyCompleted(store.downloads[idx])
            finishDownload(id: id)
        case .failure(let error):
            store.downloads[idx].status = .error
            if let key = coordinator.errorKey(for: error) {
                recordError(id: id, key: key)
            } else {
                store.downloads[idx].errorMessage = coordinator.localizedMessage(for: error)
            }
            coordinator.progress.unpublish(for: id)
            if id == priority.priorityDownloadID {
                // The priority task gave up after retries; tell the user the
                // auto-paused downloads are being resumed.
                notifier.notify(
                    title: LanguageManager.shared.localized("Priority Download Failed"),
                    body: String(
                        format: LanguageManager.shared.localized("Priority download %@ failed. Other downloads have been resumed."),
                        store.downloads[idx].filename))
            } else {
                notifier.notifyFailed(store.downloads[idx])
            }
            finishDownload(id: id)
        }
    }

    /// Completes the success path after an optional checksum verification.
    /// On a mismatch the staging file is discarded and the download is marked
    /// failed instead of being handed over as a finished file.
    private func finalizeVerifiedDownload(id: UUID, matches: Bool, staging: URL, final: URL) {
        guard let idx = store.index(of: id) else { return }
        if matches {
            store.downloads[idx].status = .completed
            try? FileManager.default.moveItem(at: staging, to: final)
            let dir = store.downloads[idx].savePath ?? AppConfig.defaultDownloadDir
            NSWorkspace.shared.noteFileSystemChanged(dir)
            notifier.notifyCompleted(store.downloads[idx])
        } else {
            store.downloads[idx].status = .error
            recordError(id: id, key: "Checksum mismatch")
            try? FileManager.default.removeItem(at: staging)
            notifier.notifyFailed(store.downloads[idx])
        }
        finishDownload(id: id)
    }

    /// Shared post-completion bookkeeping for both success and failure.
    private func finishDownload(id: UUID) {
        coordinator.endAccess(for: id)
        store.save()
        if id == priority.priorityDownloadID {
            priority.end()
        } else {
            startNextWaitingDownload()
        }
    }

    // MARK: - File integrity

    /// A snapshot of a download's staging file, safe to probe off the main
    /// thread.
    private struct MissingFile: Sendable {
        let id: UUID
        let status: DownloadStatus
        let path: String
    }

    /// Records an error state that survives language switches: stores the
    /// catalog key for re-localization at display time.
    private func checkDownloadFiles() {
        // Snapshot paths on the main thread, then probe the filesystem off-main
        // so fileExists I/O never blocks the UI.
        let toCheck = downloads.compactMap { d -> MissingFile? in
            guard d.status == .active || d.status == .paused else { return nil }
            if d.totalSize == 0, d.downloadedSize == 0 { return nil }
            return MissingFile(id: d.id, status: d.status, path: DownloadPath.staging(for: d).path)
        }
        guard !toCheck.isEmpty else { return }
        Task.detached { [weak self] in
            let missing = toCheck.filter { !FileManager.default.fileExists(atPath: $0.path) }
            guard !missing.isEmpty else { return }
            await MainActor.run {
                self?.handleMissingFiles(missing)
            }
        }
    }

    private func handleMissingFiles(_ missing: [MissingFile]) {
        for item in missing {
            guard let idx = store.index(of: item.id) else { continue }
            // Re-check the live status; it may have completed since the snapshot.
            guard downloads[idx].status == .active || downloads[idx].status == .paused else { continue }
            if downloads[idx].status == .active {
                coordinator.cancel(item.id)
                coordinator.untrack(item.id)
            }
            downloads[idx].status = .error
            recordError(id: item.id, key: "Download file has been deleted")
            coordinator.progress.unpublish(for: item.id)
            // Surface the failure like any engine error (gated by notifyFailed).
            notifier.notifyFailed(downloads[idx])
        }
        store.save()
        // A deleted in-flight download just released a concurrency slot; let the
        // next waiting task take it over.
        startNextWaitingDownload()
    }

    // MARK: - Persistence

    func checkFilesAndPersistIfNeeded() {
        checkDownloadFiles()
        coordinator.persistProgressIfNeeded()
    }

    func prepareForTermination() {
        coordinator.progress.unpublishAll()
        if downloads.contains(where: { $0.totalSize > 0 }) {
            persistence.saveImmediately(downloads)
        }
    }

    func unpublishAllProgress() {
        coordinator.progress.unpublishAll()
    }
}
