import SwiftUI
import AppKit
import Observation
import MacDLCore

@Observable
final class ContentViewModel {
    static var current: ContentViewModel?
    private static var terminationSaved = false

    var downloads: [Download] = []
    var selectedDownloads = Set<UUID>()
    var fileTypeFilter: FileTypeFilter = .all

    private let engine: DownloadEngineProtocol
    private let persistence: DownloadPersistence
    private let settings: SettingsStore
    private let progress: ProgressPublisher
    private var termObserver: NSObjectProtocol?
    private var fileCheckTimer: Timer?
    private var engineTrackedDownloads: Set<UUID> = []
    private var needsProgressSave = false
    private var lastProgressSaveTime: Date = .distantPast
    private var priorityDownloadID: UUID?
    private var pausedForPriority: Set<UUID> = []

    init(
        engine: DownloadEngineProtocol = DownloadEngine.shared,
        persistence: DownloadPersistence = .shared,
        settings: SettingsStore = .shared
    ) {
        self.engine = engine
        self.persistence = persistence
        self.settings = settings
        self.progress = ProgressPublisher()
        Self.current = self
        self.progress.setCancelHandler { [weak self] id in self?.cancelProgressDownload(id) }
        downloads = persistence.load()
        for i in downloads.indices where downloads[i].status == .active {
            downloads[i].status = .paused
        }
        pausedForPriority = Set(downloads.filter { $0.pausedForPriority == true }.map(\.id))
        let priority = downloads.first { $0.isPriorityDownload == true }?.id
        if let priority {
            priorityDownloadID = priority
            resumeDownload(id: priority)
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
            self.progress.unpublishAll()
            if self.downloads.contains(where: { $0.totalSize > 0 }) {
                self.persistence.saveImmediately(self.downloads)
            }
        }
        fileCheckTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.checkDownloadFiles()
            self.persistProgressIfNeeded()
        }
    }

    deinit {
        fileCheckTimer?.invalidate()
        progress.unpublishAll()
        if let observer = termObserver { NotificationCenter.default.removeObserver(observer) }
    }

    private func cancelProgressDownload(_ id: UUID) {
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            let d = downloads[idx]
            if d.status == .active {
                engine.pause(id: id)
            }
            downloads[idx].status = .paused
            persistence.save(downloads)
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

    // MARK: - Progress (Finder Download Badge)

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
        for i in downloads.indices {
            let d = downloads[i]
            guard d.status == .active || d.status == .paused else { continue }
            if d.totalSize == 0, d.downloadedSize == 0 { continue }
            let url = stagingURL(for: d)
            if !FileManager.default.fileExists(atPath: url.path) {
                if d.status == .active {
                    engine.cancel(id: d.id)
                    engineTrackedDownloads.remove(d.id)
                }
                downloads[i].status = .error
                downloads[i].errorMessage = LanguageManager.shared.localized("Download file has been deleted")
                progress.unpublish(for: d.id)
                persistence.save(downloads)
            }
        }
    }

    // MARK: - Download Actions

    private func progressHandler(for id: UUID) -> (Int64, Int64, Int64) -> Void {
        { [weak self] bytes, total, speed in
            DispatchQueue.main.async { [weak self] in
                guard let self, let idx = self.downloads.firstIndex(where: { $0.id == id }) else { return }
                let prevTotal = self.downloads[idx].totalSize
                self.downloads[idx].totalSize = max(total, self.downloads[idx].totalSize)
                self.downloads[idx].downloadedSize = bytes
                self.downloads[idx].downloadSpeed = speed
                self.needsProgressSave = true
                if !self.progress.isPublished(for: id) {
                    self.progress.publish(for: self.downloads[idx], fileURL: self.stagingURL(for: self.downloads[idx]))
                }
                self.progress.update(for: id, download: self.downloads[idx])
                if prevTotal == 0 {
                    DownloadPersistence.shared.save(self.downloads, caller: "progressHandler")
                }
            }
        }
    }

    private func persistProgressIfNeeded() {
        guard needsProgressSave else { return }
        let now = Date()
        guard now.timeIntervalSince(lastProgressSaveTime) >= 5 else { return }
        lastProgressSaveTime = now
        needsProgressSave = false
        persistence.save(downloads, caller: "periodicProgressSave")
    }

    private func localizedMessage(for error: Error) -> String {
        guard let dl = error as? DownloadError else { return error.localizedDescription }
        switch dl {
        case .cancelled:
            return LanguageManager.shared.localized("Cancelled")
        case .fileDeleted:
            return LanguageManager.shared.localized("Download file has been deleted")
        case .rangeNotSatisfiable:
            return LanguageManager.shared.localized("Server does not support this download range")
        case .fileChanged:
            return LanguageManager.shared.localized("File changed on server, resume not possible")
        case .network(let e):
            return String(format: LanguageManager.shared.localized("Network error: %@"), e.localizedDescription)
        }
    }

    private func installCompletionHandler(for id: UUID) {
        engine.setCompletionHandler(for: id) { [weak self] result in
            DispatchQueue.main.async { [weak self] in
                guard let self, let idx = self.downloads.firstIndex(where: { $0.id == id }) else { return }
                switch result {
                case .success:
                    self.downloads[idx].status = .completed
                    self.progress.unpublish(for: id)
                    let staging = self.stagingURL(for: self.downloads[idx])
                    let final = self.destinationURL(for: self.downloads[idx])
                    try? FileManager.default.moveItem(at: staging, to: final)
                    let dir = self.downloads[idx].savePath ?? AppConfig.defaultDownloadDir
                    NSWorkspace.shared.noteFileSystemChanged(dir)
                case .failure(let error):
                    self.downloads[idx].status = .error
                    self.downloads[idx].errorMessage = self.localizedMessage(for: error)
                    self.progress.unpublish(for: id)
                }
                self.engineTrackedDownloads.remove(id)
                self.engine.cleanup(id: id)
                self.persistence.save(self.downloads)
                if id == self.priorityDownloadID {
                    // TODO: notify when a priority task's retry budget is exhausted (together with the notifications feature)
                    self.endPriorityMode()
                } else {
                    self.startNextWaitingDownload()
                }
            }
        }
    }

    private func installResumeSupportHandler(for id: UUID) {
        engine.setResumeSupportHandler(for: id) { [weak self] supports in
            DispatchQueue.main.async { [weak self] in
                guard let self, let idx = self.downloads.firstIndex(where: { $0.id == id }) else { return }
                if self.downloads[idx].supportsResume != supports {
                    self.downloads[idx].supportsResume = supports
                    self.persistence.save(self.downloads)
                }
            }
        }
    }

    private func setupEngineTask(for id: UUID, url sourceURL: URL, dlLimit: Int) {
        let idx = downloads.firstIndex(where: { $0.id == id })
        let limit = dlLimit > 0 ? dlLimit : (idx.map { downloads[$0].downloadLimit ?? 0 } ?? 0)
        let speedLimit = Int64(limit)
        guard let src = downloads.first(where: { $0.id == id }) else { return }
        let dest = stagingURL(for: src)

        engineTrackedDownloads.insert(id)
        if let idx {
            let built = downloads[idx].ensureChunks()
            downloads[idx].chunks = built
            downloads[idx].downloadedSize = built.reduce(0) { $0 + $1.downloadedSize }
            downloads[idx].totalSize = built.last?.endOffset ?? 0
        }
        engine.start(id: id, url: sourceURL, destinationURL: dest, speedLimit: speedLimit,
                     chunkSize: downloads[idx ?? 0].chunkSize,
                     maxConcurrent: downloads[idx ?? 0].maxConcurrentChunks,
                     chunks: downloads[idx ?? 0].chunks)

        engine.setProgressHandler(for: id, handler: progressHandler(for: id))

        engine.setChunksChangeHandler(for: id) { [weak self] chunks in
            DispatchQueue.main.async { [weak self] in
                guard let self, let idx = self.downloads.firstIndex(where: { $0.id == id }) else { return }
                self.downloads[idx].chunks = chunks
            }
        }

        installResumeSupportHandler(for: id)
        installCompletionHandler(for: id)
    }

    func addDownload(url: String, savePath: String? = nil, dlLimit: Int = 0, connections: Int? = nil) {
        let name = URL(string: url)?.lastPathComponent ?? "download-\(downloads.count + 1)"
        let dir = savePath ?? AppConfig.defaultDownloadDir

        if let existing = downloads.first(where: { $0.url == url || ($0.filename == name && ($0.savePath ?? AppConfig.defaultDownloadDir) == dir) }) {
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
            downloadLimit: dlLimit > 0 ? dlLimit : nil,
            maxConcurrentChunks: connections ?? settings.maxConnections
        )
        downloads.append(d)
        persistence.save(downloads)

        guard let sourceURL = URL(string: url) else {
            if let idx = downloads.firstIndex(where: { $0.id == d.id }) {
                downloads[idx].status = .error
                downloads[idx].errorMessage = LanguageManager.shared.localized("Invalid URL")
                persistence.save(downloads)
            }
            return
        }

        let activeCount = downloads.filter { $0.status == .active && $0.id != d.id }.count
        if activeCount >= max(settings.maxConcurrentDownloads, 1),
           let idx = downloads.firstIndex(where: { $0.id == d.id }) {
            downloads[idx].status = .waiting
            persistence.save(downloads)
            return
        }

        setupEngineTask(for: d.id, url: sourceURL, dlLimit: dlLimit)
    }

    private func startNextWaitingDownload() {
        let limit = max(settings.maxConcurrentDownloads, 1)
        while downloads.filter({ $0.status == .active }).count < limit,
              let idx = downloads.firstIndex(where: { $0.status == .waiting }) {
            downloads[idx].status = .active
            persistence.save(downloads)
            guard let sourceURL = URL(string: downloads[idx].url) else {
                downloads[idx].status = .error
                downloads[idx].errorMessage = LanguageManager.shared.localized("Invalid URL")
                persistence.save(downloads)
                continue
            }
            setupEngineTask(for: downloads[idx].id, url: sourceURL, dlLimit: downloads[idx].downloadLimit ?? 0)
        }
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
        engine.pause(id: id)
        if engineTrackedDownloads.contains(id) {
            if !FileManager.default.fileExists(atPath: stagingURL(for: downloads[idx]).path) {
                downloads[idx].status = .error
                downloads[idx].errorMessage = LanguageManager.shared.localized("Download file has been deleted")
                persistence.save(downloads)
                return
            }
        }
        downloads[idx].status = .paused
        persistence.save(downloads)
    }

    func resumeDownload(id: UUID) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        guard downloads[idx].status == .paused || downloads[idx].status == .waiting else { return }

        downloads[idx].status = .active
        persistence.save(downloads)

        if engine.resume(id: id) { return }

        guard let sourceURL = URL(string: downloads[idx].url) else {
            downloads[idx].status = .error
            downloads[idx].errorMessage = LanguageManager.shared.localized("Invalid URL")
            persistence.save(downloads)
            return
        }

        let dest = stagingURL(for: downloads[idx])
        downloads[idx].chunks = downloads[idx].ensureChunks()
        let chunks = downloads[idx].chunks
        engine.start(id: id, url: sourceURL, destinationURL: dest, speedLimit: Int64(downloads[idx].downloadLimit ?? 0),
                     chunkSize: downloads[idx].chunkSize,
                     maxConcurrent: downloads[idx].maxConcurrentChunks,
                     chunks: chunks)

        engine.setProgressHandler(for: id, handler: progressHandler(for: id))

        engine.setChunksChangeHandler(for: id) { [weak self] chunks in
            DispatchQueue.main.async { [weak self] in
                guard let self, let idx = self.downloads.firstIndex(where: { $0.id == id }) else { return }
                self.downloads[idx].chunks = chunks
            }
        }

        installResumeSupportHandler(for: id)
        installCompletionHandler(for: id)
    }

    func deleteDownload(id: UUID) {
        progress.unpublish(for: id)
        if id == priorityDownloadID {
            endPriorityMode(excluding: id)
        }
        pausedForPriority.remove(id)
        guard let d = downloads.first(where: { $0.id == id }) else { return }
        if d.status == .active {
            engine.cancel(id: id)
            engineTrackedDownloads.remove(id)
        }
        let dir = d.savePath ?? AppConfig.defaultDownloadDir
        try? FileManager.default.removeItem(atPath: dir + "/" + d.filename + ".macdl")
                try? FileManager.default.removeItem(atPath: dir + "/" + d.filename)
        downloads.removeAll { $0.id == id }
        persistence.save(downloads)
    }

    func retryDownload(id: UUID) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        let d = downloads[idx]
        if d.status == .active {
            engine.cancel(id: id)
            engineTrackedDownloads.remove(id)
            progress.unpublish(for: id)
        }
        let dir = d.savePath ?? AppConfig.defaultDownloadDir
        try? FileManager.default.removeItem(atPath: dir + "/" + d.filename + ".macdl")
                try? FileManager.default.removeItem(atPath: dir + "/" + d.filename)

        downloads[idx].status = .active
        downloads[idx].errorMessage = nil
        downloads[idx].downloadedSize = 0
        downloads[idx].totalSize = 0
        downloads[idx].chunks = []
        persistence.save(downloads)

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
        persistence.save(downloads)
        engine.setSpeedLimit(id: id, limit: Int64(limit))
    }

    func setMaxChunks(id: UUID, count: Int) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[idx].maxConcurrentChunks = count
        persistence.save(downloads)
        engine.setMaxConcurrent(id: id, max: count)
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
            engine.pause(id: downloads[i].id)
            downloads[i].status = .paused
        }
        persistence.save(downloads)
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
                    engine.pause(id: old)
                    downloads[oi].status = .paused
                }
            }
            pausedForPriority.insert(old)
        }

        // Pause other active tasks (only those auto-paused for this priority)
        for i in downloads.indices where downloads[i].id != id && downloads[i].status == .active {
            engine.pause(id: downloads[i].id)
            downloads[i].status = .paused
            downloads[i].pausedForPriority = true
            pausedForPriority.insert(downloads[i].id)
        }

        priorityDownloadID = id
        if let ii = downloads.firstIndex(where: { $0.id == id }) {
            downloads[ii].isPriorityDownload = true
        }
        persistence.save(downloads)
    }

    func cancelPriorityDownload(id: UUID) {
        guard id == priorityDownloadID else { return }
        endPriorityMode()
    }

    private func endPriorityMode(excluding skip: UUID? = nil) {
        priorityDownloadID = nil
        let toResume = pausedForPriority
        pausedForPriority.removeAll()
        for i in downloads.indices {
            downloads[i].isPriorityDownload = false
            if toResume.contains(downloads[i].id),
               downloads[i].id != skip,
               downloads[i].pausedForPriority == true {
                downloads[i].pausedForPriority = false
                resumeDownload(id: downloads[i].id)
            }
        }
        persistence.save(downloads)
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
            progress.unpublish(for: d.id)
            if d.status == .active {
                engine.cancel(id: d.id)
                engineTrackedDownloads.remove(d.id)
            }
            let dir = d.savePath ?? AppConfig.defaultDownloadDir
            if deleteFiles {
                try? FileManager.default.removeItem(atPath: dir + "/" + d.filename + ".macdl")
                try? FileManager.default.removeItem(atPath: dir + "/" + d.filename)
            }
        }

        downloads.removeAll { selectedDownloads.contains($0.id) }
        selectedDownloads.removeAll()
        persistence.save(downloads)
    }
}
