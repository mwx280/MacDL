import SwiftUI
import AppKit
import Observation

@Observable
final class ContentViewModel {
    static weak var current: ContentViewModel?

    var downloads: [Download] = []
    var selectedDownloads = Set<UUID>()
    var fileTypeFilter: FileTypeFilter = .all

    private let engine = DownloadEngine.shared
    private let persistence = DownloadPersistence.shared
    private var termObserver: NSObjectProtocol?
    private var progressMap: [UUID: Progress] = [:]
    private var fileCheckTimer: Timer?
    private var engineTrackedDownloads: Set<UUID> = []

    init() {
        Self.current = self
        downloads = persistence.load()
        for i in downloads.indices where downloads[i].status == .active {
            downloads[i].status = .paused
        }
        termObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.fileCheckTimer?.invalidate()
            self.fileCheckTimer = nil
            self.unpublishAllProgress()
            if self.downloads.contains(where: { $0.totalSize > 0 }) {
                self.persistence.saveImmediately(self.downloads)
            }
        }
        fileCheckTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkDownloadFiles()
        }
    }

    deinit {
        fileCheckTimer?.invalidate()
        unpublishAllProgress()
        if let observer = termObserver { NotificationCenter.default.removeObserver(observer) }
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
        let dir = download.savePath ?? RPCConfig.defaultDownloadDir
        return URL(fileURLWithPath: dir + "/" + download.filename)
    }

    private func publishProgress(for download: Download) {
        let fileURL = destinationURL(for: download)
        let downloadID = download.id

        let p = Progress(totalUnitCount: max(download.totalSize, 1))
        p.kind = .file
        p.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        p.setUserInfoObject(fileURL, forKey: .fileURLKey)
        p.completedUnitCount = download.downloadedSize
        p.cancellationHandler = { [weak self] in
            guard let self else { return }
            self.unpublishProgress(for: downloadID)
            if let idx = self.downloads.firstIndex(where: { $0.id == downloadID }) {
                let d = self.downloads[idx]
                if d.status == .active {
                    self.engine.pause(id: downloadID)
                }
                self.downloads[idx].status = .paused
            }
        }
        p.publish()
        progressMap[download.id] = p
    }

    private func updateProgress(for id: UUID) {
        guard let d = downloads.first(where: { $0.id == id }),
              let p = progressMap[id]
        else { return }
        p.totalUnitCount = max(d.totalSize, 1)
        p.completedUnitCount = d.downloadedSize
        p.isCancellable = d.status == .active
    }

    private func unpublishProgress(for id: UUID) {
        guard let p = progressMap.removeValue(forKey: id) else { return }
        p.unpublish()
    }

    private func unpublishAllProgress() {
        for (_, p) in progressMap { p.unpublish() }
        progressMap.removeAll()
    }

    // MARK: - File Integrity

    private func checkDownloadFiles() {
        for i in downloads.indices {
            let d = downloads[i]
            guard d.status == .active || d.status == .paused else { continue }
            let url = destinationURL(for: d)
            if !FileManager.default.fileExists(atPath: url.path) {
                if d.status == .active {
                    engine.cancel(id: d.id)
                    engineTrackedDownloads.remove(d.id)
                }
                downloads[i].status = .error
                downloads[i].errorMessage = LanguageManager.shared.localized("Download file has been deleted")
                unpublishProgress(for: d.id)
                persistence.save(downloads)
            }
        }
    }

    // MARK: - Download Actions

    private func progressHandler(for id: UUID) -> (Int64, Int64, Int64) -> Void {
        { [weak self] bytes, total, speed in
            guard let self, let idx = self.downloads.firstIndex(where: { $0.id == id }) else { return }
            let prevTotal = self.downloads[idx].totalSize
            self.downloads[idx].totalSize = max(total, self.downloads[idx].totalSize)
            self.downloads[idx].downloadedSize = bytes
            self.downloads[idx].downloadSpeed = speed
            print("📊 progress: bytes=\(bytes) total=\(total) prevTotal=\(prevTotal)")
            if self.progressMap[id] == nil {
                self.publishProgress(for: self.downloads[idx])
            }
            self.updateProgress(for: id)
            if prevTotal == 0 {
                print("📊 progress -> saving")
                DownloadPersistence.shared.save(self.downloads, caller: "progressHandler")
            }
        }
    }

    private func setupEngineTask(for id: UUID, url sourceURL: URL, dlLimit: Int) {
        let idx = downloads.firstIndex(where: { $0.id == id })
        let limit = dlLimit > 0 ? dlLimit : (idx.map { downloads[$0].downloadLimit ?? 0 } ?? 0)
        let speedLimit = Int64(limit)
        guard let src = downloads.first(where: { $0.id == id }) else { return }
        let dest = destinationURL(for: src)

        engineTrackedDownloads.insert(id)
        engine.start(id: id, url: sourceURL, destinationURL: dest, speedLimit: speedLimit)
        if let idx {
            downloads[idx].downloadedSize = 0
            downloads[idx].totalSize = 0
        }

        engine.setProgressHandler(for: id, handler: progressHandler(for: id))

        engine.setCompletionHandler(for: id) { [weak self] result in
            guard let self, let idx = self.downloads.firstIndex(where: { $0.id == id }) else { return }
            switch result {
            case .success:
                self.downloads[idx].status = .completed
                self.unpublishProgress(for: id)
                let dir = self.downloads[idx].savePath ?? RPCConfig.defaultDownloadDir
                NSWorkspace.shared.noteFileSystemChanged(dir)
            case .failure(let error):
                self.downloads[idx].status = .error
                self.downloads[idx].errorMessage = error.localizedDescription
                self.unpublishProgress(for: id)
            }
            self.engineTrackedDownloads.remove(id)
            self.persistence.save(self.downloads)
        }
    }

    func addDownload(url: String, savePath: String? = nil, dlLimit: Int = 0) {
        let name = URL(string: url)?.lastPathComponent ?? "download-\(downloads.count + 1)"
        let dir = savePath ?? RPCConfig.defaultDownloadDir

        if let existing = downloads.first(where: { $0.url == url || ($0.filename == name && ($0.savePath ?? RPCConfig.defaultDownloadDir) == dir) }) {
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
            downloadLimit: dlLimit > 0 ? dlLimit : nil
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

        setupEngineTask(for: d.id, url: sourceURL, dlLimit: dlLimit)
    }

    func pauseDownload(id: UUID) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }), downloads[idx].status == .active else { return }
        engine.pause(id: id)
        if engineTrackedDownloads.contains(id) {
            if !FileManager.default.fileExists(atPath: destinationURL(for: downloads[idx]).path) {
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

        let dest = destinationURL(for: downloads[idx])
        let persisted = downloads[idx].downloadedSize
        engine.start(id: id, url: sourceURL, destinationURL: dest, speedLimit: Int64(downloads[idx].downloadLimit ?? 0), resumeFrom: persisted)

        engine.setProgressHandler(for: id, handler: progressHandler(for: id))

        engine.setCompletionHandler(for: id) { [weak self] result in
            guard let self, let idx = self.downloads.firstIndex(where: { $0.id == id }) else { return }
            switch result {
            case .success:
                self.downloads[idx].status = .completed
                self.unpublishProgress(for: id)
                let dir = self.downloads[idx].savePath ?? RPCConfig.defaultDownloadDir
                NSWorkspace.shared.noteFileSystemChanged(dir)
            case .failure(let error):
                self.downloads[idx].status = .error
                self.downloads[idx].errorMessage = error.localizedDescription
                self.unpublishProgress(for: id)
            }
            self.persistence.save(self.downloads)
        }
    }

    func deleteDownload(id: UUID) {
        unpublishProgress(for: id)
        guard let d = downloads.first(where: { $0.id == id }) else { return }
        if d.status == .active {
            engine.cancel(id: id)
            engineTrackedDownloads.remove(id)
        }
        let dir = d.savePath ?? RPCConfig.defaultDownloadDir
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
            unpublishProgress(for: id)
        }
        let dir = d.savePath ?? RPCConfig.defaultDownloadDir
        try? FileManager.default.removeItem(atPath: dir + "/" + d.filename)

        downloads[idx].status = .active
        downloads[idx].errorMessage = nil
        downloads[idx].downloadedSize = 0
        downloads[idx].totalSize = 0
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

        for d in toDelete {
            unpublishProgress(for: d.id)
            if d.status == .active {
                engine.cancel(id: d.id)
                engineTrackedDownloads.remove(d.id)
            }
            let dir = d.savePath ?? RPCConfig.defaultDownloadDir
            if deleteFiles {
                try? FileManager.default.removeItem(atPath: dir + "/" + d.filename)
            }
        }

        downloads.removeAll { selectedDownloads.contains($0.id) }
        selectedDownloads.removeAll()
        persistence.save(downloads)
    }
}
