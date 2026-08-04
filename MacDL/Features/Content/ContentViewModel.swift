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

    private let store: DownloadStore
    private let engine: DownloadEngineProtocol
    private let coordinator: DownloadEngineCoordinator
    private let persistence: DownloadPersistence
    private let settings: SettingsStore
    private let notifier: DownloadNotifier
    private var termObserver: NSObjectProtocol?
    private var redownloadObserver: NSObjectProtocol?
    private var fileCheckTimer: Timer?
    private var priorityDownloadID: UUID?
    private var pausedForPriority: Set<UUID> = []

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
        Self.current = self
        coordinator.progress.setCancelHandler { [weak self] id in self?.cancelProgressDownload(id) }
        coordinator.onTaskCompletion = { [weak self] id, result in
            self?.handleEngineCompletion(id: id, result: result)
        }

        for i in store.downloads.indices where store.downloads[i].status == .active {
            store.downloads[i].status = .paused
        }
        pausedForPriority = Set(store.downloads.filter { $0.pausedForPriority == true }.map(\.id))

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

    private func destinationURL(for download: Download) -> URL {
        let dir = download.savePath ?? AppConfig.defaultDownloadDir
        return URL(fileURLWithPath: dir + "/" + download.filename)
    }

    private func stagingURL(for download: Download) -> URL {
        let dir = download.savePath ?? AppConfig.defaultDownloadDir
        return URL(fileURLWithPath: dir + "/" + download.filename + ".macdl")
    }

    // MARK: - File Integrity

    private func checkDownloadFiles() {
        // Snapshot paths on the main thread, then probe the filesystem off-main
        // so fileExists I/O never blocks the UI.
        let toCheck = downloads.compactMap { d -> (id: UUID, status: DownloadStatus, path: String)? in
            guard d.status == .active || d.status == .paused else { return nil }
            if d.totalSize == 0, d.downloadedSize == 0 { return nil }
            return (d.id, d.status, stagingURL(for: d).path)
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
            downloads[idx].errorMessage = LanguageManager.shared.localized("Download file has been deleted")
            coordinator.progress.unpublish(for: item.id)
        }
        store.save()
    }

    // MARK: - Engine completion

    private func handleEngineCompletion(id: UUID, result: Result<Void, Error>) {
        guard let idx = store.index(of: id) else { return }
        switch result {
        case .success:
            store.downloads[idx].status = .completed
            coordinator.progress.unpublish(for: id)
            let staging = stagingURL(for: store.downloads[idx])
            let final = destinationURL(for: store.downloads[idx])
            try? FileManager.default.moveItem(at: staging, to: final)
            let dir = store.downloads[idx].savePath ?? AppConfig.defaultDownloadDir
            NSWorkspace.shared.noteFileSystemChanged(dir)
            notifier.notifyCompleted(store.downloads[idx])
        case .failure(let error):
            store.downloads[idx].status = .error
            store.downloads[idx].errorMessage = coordinator.localizedMessage(for: error)
            coordinator.progress.unpublish(for: id)
            if id == priorityDownloadID {
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
        if id == priorityDownloadID {
            endPriorityMode()
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
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil,
           (engine as AnyObject) === DownloadEngine.shared {
            return
        }
        let name = URL(string: url)?.lastPathComponent ?? "download-\(downloads.count + 1)"
        let dir = savePath ?? AppConfig.defaultDownloadDir

        if !allowDuplicate, let existing = downloads.first(where: { $0.url == url || ($0.filename == name && ($0.savePath ?? AppConfig.defaultDownloadDir) == dir) }) {
            let alert = NSAlert()
            switch existing.status {
            case .active, .waiting:
                alert.messageText = LanguageManager.shared.localized("Duplicate URL")
                alert.informativeText = LanguageManager.shared.localized("The URL is already in the download queue")
                alert.addButton(withTitle: LanguageManager.shared.localized("OK"))
                alert.runModal()
                return
            case .paused:
                alert.messageText = LanguageManager.shared.localized("Paused Download")
                alert.informativeText = LanguageManager.shared.localized("A paused download for this file already exists. Resume it?")
                alert.addButton(withTitle: LanguageManager.shared.localized("Resume"))
                alert.addButton(withTitle: LanguageManager.shared.localized("New Download"))
                alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
                let resp = alert.runModal()
                if resp == .alertFirstButtonReturn { resumeDownload(id: existing.id) }
                if resp != .alertSecondButtonReturn { return }
            case .completed:
                alert.messageText = LanguageManager.shared.localized("Completed Download")
                alert.informativeText = LanguageManager.shared.localized("This file has already been downloaded. Download again?")
                alert.addButton(withTitle: LanguageManager.shared.localized("Download Again"))
                alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
                if alert.runModal() != .alertFirstButtonReturn { return }
            case .error, .stopped:
                alert.messageText = LanguageManager.shared.localized("Failed Download")
                let reason = existing.errorMessage ?? LanguageManager.shared.localized("Unknown error")
                alert.informativeText = String(format: LanguageManager.shared.localized("Previous download failed: %@. Retry?"), reason)
                alert.addButton(withTitle: LanguageManager.shared.localized("Retry"))
                alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
                if alert.runModal() != .alertFirstButtonReturn { return }
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
                $0.errorMessage = LanguageManager.shared.localized("Download folder access lost. Choose it again in Settings.")
            }
            store.save()
            return
        }
        let dest = stagingURL(for: src)
        let speedLimit = Int64(dlLimit > 0 ? dlLimit : (src.downloadLimit ?? 0))
        coordinator.start(id: id, url: sourceURL, dest: dest, speedLimit: speedLimit,
                          chunkSize: src.chunkSize,
                          maxConcurrent: src.maxConcurrentChunks,
                          chunks: src.chunks)
    }

    func pauseDownload(id: UUID) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }), downloads[idx].status == .active else { return }
        if downloads[idx].supportsResume == false {
            let alert = NSAlert()
            alert.messageText = LanguageManager.shared.localized("Pause non-resumable download?")
            alert.informativeText = LanguageManager.shared.localized("This download does not support resuming. Pausing it means it must restart from the beginning. Pause anyway?")
            alert.addButton(withTitle: LanguageManager.shared.localized("Pause"))
            alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        coordinator.pause(id)
        if coordinator.isTracked(id) {
            if !FileManager.default.fileExists(atPath: stagingURL(for: downloads[idx]).path) {
                downloads[idx].status = .error
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
            downloads[idx].errorMessage = LanguageManager.shared.localized("Download folder access lost. Choose it again in Settings.")
            store.save()
            return
        }

        downloads[idx].status = .active
        store.save()

        if coordinator.resume(id) { return }

        guard let sourceURL = URL(string: downloads[idx].url) else {
            downloads[idx].status = .error
            downloads[idx].errorMessage = LanguageManager.shared.localized("Invalid URL")
            store.save()
            return
        }

        let dest = stagingURL(for: downloads[idx])
        coordinator.start(id: id, url: sourceURL, dest: dest,
                          speedLimit: Int64(downloads[idx].downloadLimit ?? 0),
                          chunkSize: downloads[idx].chunkSize,
                          maxConcurrent: downloads[idx].maxConcurrentChunks,
                          chunks: downloads[idx].chunks)
    }

    func deleteDownload(id: UUID) {
        coordinator.progress.unpublish(for: id)
        coordinator.endAccess(for: id)
        if id == priorityDownloadID {
            endPriorityMode(excluding: id)
        }
        pausedForPriority.remove(id)
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
        let alert = NSAlert()
        alert.messageText = LanguageManager.shared.localized("Redownload")
        if fileExists {
            alert.informativeText = String(
                format: LanguageManager.shared.localized("%@ already exists and will be overwritten. Download it again?"),
                download.filename)
        } else {
            alert.informativeText = String(
                format: LanguageManager.shared.localized("Download %@ again?"),
                download.filename)
        }
        alert.addButton(withTitle: LanguageManager.shared.localized("Redownload"))
        alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
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
        downloads[idx].downloadedSize = 0
        downloads[idx].totalSize = 0
        downloads[idx].chunks = []
        downloads[idx].supportsResume = nil
        store.save()

        guard let sourceURL = URL(string: d.url) else {
            downloads[idx].status = .error
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
        downloads[idx].downloadedSize = 0
        downloads[idx].totalSize = 0
        downloads[idx].chunks = []
        store.save()

        guard let sourceURL = URL(string: d.url) else {
            downloads[idx].status = .error
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
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        guard [.active, .paused, .waiting].contains(downloads[idx].status) else { return }
        // Ensure the target is active
        if downloads[idx].status == .paused || downloads[idx].status == .waiting {
            resumeDownload(id: id)
        }

        // Replace: pause the old priority task and add it to the resume set
        if let old = priorityDownloadID, old != id {
            if let oi = downloads.firstIndex(where: { $0.id == old }) {
                downloads[oi].isPriorityDownload = false
                if downloads[oi].status == .active {
                    coordinator.pause(old)
                    downloads[oi].status = .paused
                }
            }
            pausedForPriority.insert(old)
        }

        // Pause other active tasks (only those auto-paused for this priority)
        for i in downloads.indices where downloads[i].id != id && downloads[i].status == .active {
            coordinator.pause(downloads[i].id)
            downloads[i].status = .paused
            downloads[i].pausedForPriority = true
            pausedForPriority.insert(downloads[i].id)
        }

        priorityDownloadID = id
        if let ii = downloads.firstIndex(where: { $0.id == id }) {
            downloads[ii].isPriorityDownload = true
        }
        store.save()
    }

    func cancelPriorityDownload(id: UUID) {
        guard id == priorityDownloadID else { return }
        endPriorityMode()
    }

    private func endPriorityMode(excluding skip: UUID? = nil) {
        priorityDownloadID = nil
        let toResume = pausedForPriority
        pausedForPriority.removeAll()
        // Resume everything we auto-paused for the priority task, unless it was
        // the one being deleted.
        for i in downloads.indices {
            downloads[i].isPriorityDownload = false
            if toResume.contains(downloads[i].id),
               downloads[i].id != skip,
               downloads[i].pausedForPriority == true {
                downloads[i].pausedForPriority = false
                resumeDownload(id: downloads[i].id)
            }
        }
        store.save()
    }

    func confirmDelete() {
        let alert = NSAlert()
        alert.messageText = String(format: LanguageManager.shared.localized("Are you sure you want to delete %lld download(s)?"), selectedDownloads.count)
        alert.alertStyle = .warning
        alert.addButton(withTitle: LanguageManager.shared.localized("Delete"))
        alert.addButton(withTitle: LanguageManager.shared.localized("Cancel"))

        let cb = NSButton(checkboxWithTitle: LanguageManager.shared.localized("Also remove downloaded files"), target: nil, action: nil)
        cb.state = .on
        alert.accessoryView = cb

        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            clearSelected(deleteFiles: cb.state == .on)
        }
    }

    private func clearSelected(deleteFiles: Bool = false) {
        let toDelete = downloads.filter { selectedDownloads.contains($0.id) }

        if let pid = priorityDownloadID, toDelete.contains(where: { $0.id == pid }) {
            endPriorityMode(excluding: pid)
        }
        for id in toDelete.map(\.id) { pausedForPriority.remove(id) }

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
