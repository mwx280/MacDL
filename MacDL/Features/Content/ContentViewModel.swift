import SwiftUI
import AppKit
import Observation
import MacDLCore

@Observable
final class ContentViewModel {
    // One instance for the whole app session: reopening a window reuses it, so
    // downloads keep their real state instead of being forced to paused.
    static let shared = ContentViewModel()
    static var current: ContentViewModel?
    private static var terminationSaved = false

    // Downloads live in the store; these computed properties keep the same
    // public surface that SwiftUI and the tests bind to.
    var downloads: [Download] {
        get { store.downloads }
        set { store.downloads = newValue }
    }
    var selectedDownloads = Set<UUID>()
    var fileTypeFilter: FileTypeFilter = .all
    /// Downloads currently in the range-probe/detection phase (transient, not persisted).
    var probingDownloads = Set<UUID>()

    private let store: DownloadStore
    private let engine: DownloadEngineProtocol
    private let coordinator: DownloadEngineCoordinator
    private let persistence: DownloadPersistence
    private let settings: SettingsStore
    private let notifier: DownloadNotifier
    private var termObserver: NSObjectProtocol?
    private var redownloadObserver: NSObjectProtocol?
    private var fileCheckTimer: Timer?
    private var priority: PriorityDownloadCoordinator!

    init(
        engine: DownloadEngineProtocol = DownloadEngine.shared,
        persistence: DownloadPersistence = .shared,
        settings: SettingsStore = .shared,
        notifier: DownloadNotifier = .shared
    ) {
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
        Self.current = self
        coordinator.progress.setCancelHandler { [weak self] id in self?.cancelProgressDownload(id) }
        coordinator.onTaskCompletion = { [weak self] id, result in
            self?.handleEngineCompletion(id: id, result: result)
        }
        coordinator.onPhaseChange = { [weak self] id, isProbing in
            guard let self else { return }
            if isProbing { self.probingDownloads.insert(id) } else { self.probingDownloads.remove(id) }
        }

        for i in store.downloads.indices where store.downloads[i].status == .active {
            store.downloads[i].status = .paused
        }
        priority.restoreFromStore()
    }

    /// Sets up the app-wide observers and file-check timer. Called exactly once
    /// from the real app (MacDLApp). Tests must NOT call this per-instance:
    /// the global .requestRedownload observer and the repeating timer would
    /// leak across suites in the parallel test host and corrupt each other's
    /// downloads.
    func startAppServices() {
        guard termObserver == nil, redownloadObserver == nil, fileCheckTimer == nil else { return }
        redownloadObserver = NotificationCenter.default.addObserver(
            forName: .requestRedownload,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self, let url = note.object as? String else { return }
            self.addDownload(url: url, allowDuplicate: true)
        }
        termObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            guard !Self.terminationSaved else { return }
            Self.terminationSaved = true
            self.fileCheckTimer?.invalidate()
            self.fileCheckTimer = nil
            self.coordinator.progress.unpublishAll()
            if self.downloads.contains(where: { $0.totalSize > 0 }) {
                self.persistence.saveImmediately(self.downloads)
            }
        }
        fileCheckTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.checkDownloadFiles()
            self.coordinator.persistProgressIfNeeded()
        }
    }

    /// Tears down the observers/timer installed by startAppServices(). Tests call
    /// this after exercising the app flow so nothing leaks into other suites.
    func stopAppServices() {
        if let observer = redownloadObserver {
            NotificationCenter.default.removeObserver(observer)
            redownloadObserver = nil
        }
        if let observer = termObserver {
            NotificationCenter.default.removeObserver(observer)
            termObserver = nil
        }
        fileCheckTimer?.invalidate()
        fileCheckTimer = nil
    }

    deinit {
        fileCheckTimer?.invalidate()
        coordinator.progress.unpublishAll()
        if let observer = termObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = redownloadObserver { NotificationCenter.default.removeObserver(observer) }
    }

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

    // MARK: - Filtering

    func filteredDownloads(for item: SidebarItem?) -> [Download] {
        let statusFiltered: [Download]
        switch item {
        case .none, .all: statusFiltered = downloads
        case .active: statusFiltered = downloads.filter { $0.status == .active }
        case .waiting: statusFiltered = downloads.filter { $0.status == .waiting }
        case .completed: statusFiltered = downloads.filter { $0.status == .completed }
        case .stopped: statusFiltered = downloads.filter { $0.status == .stopped || $0.status == .error }
        }
        guard fileTypeFilter != .all else { return statusFiltered }
        return statusFiltered.filter { fileTypeFilter.matches($0) }
    }

    // MARK: - File Paths

    // Paths are derived through DownloadPath so the coordinator and this view
    // model always agree on the ".macdl" staging convention.

    // MARK: - File Integrity

    /// Records an error state that survives language switches: stores the
    /// catalog key for re-localization at display time, plus the currently
    /// localized text as a fallback for legacy readers.
    private func recordError(id: UUID, key: String) {
        store.update(id) {
            $0.errorKey = key
            $0.errorMessage = LanguageManager.shared.localized(key)
        }
    }

    private func checkDownloadFiles() {
        // Snapshot paths on the main thread, then probe the filesystem off-main
        // so fileExists I/O never blocks the UI.
        let toCheck = downloads.compactMap { d -> (id: UUID, status: DownloadStatus, path: String)? in
            guard d.status == .active || d.status == .paused else { return nil }
            if d.totalSize == 0, d.downloadedSize == 0 { return nil }
            return (d.id, d.status, DownloadPath.staging(for: d).path)
        }
        guard !toCheck.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let missing = toCheck.filter { !FileManager.default.fileExists(atPath: $0.path) }
            guard !missing.isEmpty else { return }
            DispatchQueue.main.async {
                self?.handleMissingFiles(missing)
            }
        }
    }

    private func handleMissingFiles(_ missing: [(id: UUID, status: DownloadStatus, path: String)]) {
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
        }
        store.save()
    }

    // MARK: - Engine completion

    private func handleEngineCompletion(id: UUID, result: Result<Void, Error>) {
        probingDownloads.remove(id)
        guard let idx = store.index(of: id) else { return }
        switch result {
        case .success:
            store.downloads[idx].status = .completed
            coordinator.progress.unpublish(for: id)
            let staging = DownloadPath.staging(for: store.downloads[idx])
            let final = DownloadPath.destination(for: store.downloads[idx])
            try? FileManager.default.moveItem(at: staging, to: final)
            let dir = store.downloads[idx].savePath ?? AppConfig.defaultDownloadDir
            NSWorkspace.shared.noteFileSystemChanged(dir)
            notifier.notifyCompleted(store.downloads[idx])
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
        }
        coordinator.endAccess(for: id)
        store.save()
        if id == priority.priorityDownloadID {
            priority.end()
        } else {
            startNextWaitingDownload()
        }
    }

    // MARK: - Clipboard / Links

    // Pulls http/https URLs out of arbitrary text (whitespace / newline separated).
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
        let name = URL(string: url)?.lastPathComponent ?? "download-\(downloads.count + 1)"
        let dir = savePath ?? AppConfig.defaultDownloadDir

        if !allowDuplicate, let existing = downloads.first(where: { $0.url == url || ($0.filename == name && ($0.savePath ?? AppConfig.defaultDownloadDir) == dir) }) {
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
            url: url,
            status: .active,
            savePath: savePath,
            saveBookmark: saveBookmark,
            downloadLimit: dlLimit > 0 ? dlLimit : nil,
            maxConcurrentChunks: connections ?? settings.maxConnections
        )
        store.append(d)
        store.save()

        guard let sourceURL = URL(string: url) else {
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

    /// Confirmation prompt for re-downloading a finished file. Injectable so tests
    /// can decide without presenting an NSAlert. `fileExists` tells whether the
    /// destination file is already on disk (the dialog warns it will be overwritten).
    var redownloadConfirmation: (Download, Bool) -> Bool = { download, fileExists in
        DialogPresenter.confirmRedownload(filename: download.filename, fileExists: fileExists)
    }

    /// Re-downloads a finished download. Confirms first; if the destination file
    /// already exists the dialog warns that it will be overwritten.
    func redownloadDownload(id: UUID) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        let d = downloads[idx]
        guard d.status == .completed else { return }

        let dir = d.savePath ?? AppConfig.defaultDownloadDir
        let finalPath = dir + "/" + d.filename
        let fileExists = FileManager.default.fileExists(atPath: finalPath)

        guard redownloadConfirmation(d, fileExists) else { return }

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

    func pauseAll() {
        let ids = downloads.filter { selectedDownloads.contains($0.id) && $0.status == .active }.map(\.id)
        for id in ids { pauseDownload(id: id) }
    }

    func resumeAll() {
        let ids = downloads.filter { selectedDownloads.contains($0.id) && ($0.status == .paused || $0.status == .waiting) }.map(\.id)
        for id in ids { resumeDownload(id: id) }
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

    func confirmDelete() {
        let result = DialogPresenter.confirmBulkDelete(count: selectedDownloads.count)
        if result.confirmed {
            clearSelected(deleteFiles: result.deleteFiles)
        }
    }

    private func clearSelected(deleteFiles: Bool = false) {
        let toDelete = downloads.filter { selectedDownloads.contains($0.id) }

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
        selectedDownloads.removeAll()
        store.save()
    }
}
