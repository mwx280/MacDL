import SwiftUI
import AppKit
import Observation

@Observable
final class ContentViewModel {
    var downloads: [Download] = []
    var selectedDownloads = Set<UUID>()
    var fileTypeFilter: FileTypeFilter = .all
    var isPolling = false

    private let rpc = Aria2RPCClient.shared
    private let persistence = DownloadPersistence.shared
    private var pollingTask: Task<Void, Never>?
    private var termObserver: NSObjectProtocol?
    private var progressMap: [UUID: Progress] = [:]

    init() {
        downloads = persistence.load()
        termObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.stopPolling()
            self.unpublishAllProgress()
            self.persistence.saveImmediately(self.downloads)
        }
        startPolling()
    }

    deinit {
        stopPolling()
        unpublishAllProgress()
        if let observer = termObserver { NotificationCenter.default.removeObserver(observer) }
    }

    var totalSpeed: Int64 { downloads.reduce(0) { $0 + $1.downloadSpeed } }
    var totalUpload: Int64 { downloads.reduce(0) { $0 + $1.uploadSpeed } }

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

    // MARK: - Polling

    func startPolling() {
        guard !isPolling else { return }
        isPolling = true
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if rpc.isConnected {
                    await self.syncFromRPC()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    // MARK: - Progress (Finder Download Badge)

    private func downloadDir(for download: Download) -> String {
        download.savePath ?? RPCConfig.defaultDownloadDir
    }

    private func downloadURL(for download: Download) -> URL {
        URL(fileURLWithPath: downloadDir(for: download) + "/" + download.filename + ".aria2desk")
    }

    private func hideAria2File(for download: Download) {
        let path = downloadDir(for: download) + "/" + download.filename + ".aria2desk/" + download.filename + ".aria2"
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return }
        try? (url as NSURL).setResourceValue(true, forKey: .isHiddenKey)
    }

    private func publishProgress(for download: Download) {
        guard download.gid != nil else { return }
        hideAria2File(for: download)
        let fileURL = downloadURL(for: download)

        let p = Progress(totalUnitCount: max(download.totalSize, 1))
        p.kind = .file
        p.setUserInfoObject(Progress.FileOperationKind.downloading, forKey: .fileOperationKindKey)
        p.setUserInfoObject(fileURL, forKey: .fileURLKey)
        p.completedUnitCount = download.downloadedSize
        p.publish()
        progressMap[download.id] = p
    }

    private func updateProgress(for id: UUID) {
        guard let d = downloads.first(where: { $0.id == id }),
              let p = progressMap[id]
        else { return }
        p.totalUnitCount = max(d.totalSize, 1)
        p.completedUnitCount = d.downloadedSize
    }

    private func unpublishProgress(for id: UUID) {
        guard let p = progressMap.removeValue(forKey: id) else { return }
        p.unpublish()
    }

    private func unpublishAllProgress() {
        for (_, p) in progressMap { p.unpublish() }
        progressMap.removeAll()
    }

    private func syncFromRPC() async {
        let remoteDownloads = await rpc.fetchAllDownloads()
        if Task.isCancelled { return }

        var gidToDownload: [String: Download] = [:]
        for d in downloads {
            if let gid = d.gid { gidToDownload[gid] = d }
        }

        var seenGIDs = Set<String>()
        var merged: [Download] = []

        for remote in remoteDownloads {
            guard let gid = remote.gid else { continue }
            seenGIDs.insert(gid)

            if let existing = gidToDownload[gid] {
                var updated = existing
                let prevStatus = existing.status
                updated.totalSize = remote.totalSize
                updated.downloadedSize = remote.downloadedSize
                updated.downloadSpeed = remote.downloadSpeed
                updated.uploadSpeed = remote.uploadSpeed
                updated.status = remote.status
                if updated.filename == "unknown" || updated.filename.isEmpty {
                    updated.filename = remote.filename
                }
                if prevStatus != .completed && remote.status == .completed {
                    unpublishProgress(for: updated.id)
                    await finalizeDownload(&updated)
                } else {
                    updateProgress(for: updated.id)
                }
                if remote.status == .active || remote.status == .waiting {
                    hideAria2File(for: updated)
                }
                if remote.status == .active, progressMap[updated.id] == nil {
                    publishProgress(for: updated)
                }
                if remote.status == .error || remote.status == .stopped {
                    unpublishProgress(for: updated.id)
                }
                merged.append(updated)
            } else {
                if remote.status == .active {
                    publishProgress(for: remote)
                }
                merged.append(remote)
            }
        }

        for d in downloads {
            if d.gid == nil {
                merged.append(d)
            } else if let gid = d.gid, !seenGIDs.contains(gid) {
                if d.status == .active || d.status == .waiting || d.status == .paused {
                    unpublishProgress(for: d.id)
                }
                merged.append(d)
            }
        }

        downloads = merged
        persistence.save(downloads)
    }

    private func finalizeDownload(_ d: inout Download) async {
        let dir = d.savePath ?? RPCConfig.defaultDownloadDir
        let packageDir = dir + "/" + d.filename + ".aria2desk"
        let sourcePath = packageDir + "/" + d.filename
        let targetPath = dir + "/" + d.filename

        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        if fm.fileExists(atPath: sourcePath) {
            try? fm.moveItem(atPath: sourcePath, toPath: targetPath)
        }
        try? fm.removeItem(atPath: packageDir)
    }

    // MARK: - Download Actions

    func addDownload(url: String, savePath: String? = nil, connections: Int? = nil) {
        let name = URL(string: url)?.lastPathComponent ?? "download-\(downloads.count + 1)"

        let d = Download(
            filename: name,
            url: url,
            status: .waiting,
            savePath: savePath,
            connections: connections
        )
        downloads.append(d)
        persistence.save(downloads)

        Task {
            let gid = await rpc.addDownload(url: url, savePath: savePath, connections: connections)
            if let idx = downloads.firstIndex(where: { $0.id == d.id }) {
                if let gid {
                    downloads[idx].gid = gid
                } else {
                    downloads[idx].status = .error
                }
                persistence.save(downloads)
            }
        }
    }

    func pauseDownload(id: UUID) {
        guard let d = downloads.first(where: { $0.id == id }) else { return }
        if let gid = d.gid {
            Task { await rpc.pauseDownload(gid: gid) }
        }
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].status = .paused
            persistence.save(downloads)
        }
    }

    func resumeDownload(id: UUID) {
        guard let d = downloads.first(where: { $0.id == id }) else { return }
        if let gid = d.gid {
            Task { await rpc.resumeDownload(gid: gid) }
        }
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].status = .active
            if progressMap[id] == nil { publishProgress(for: downloads[idx]) }
            persistence.save(downloads)
        }
    }

    func deleteDownload(id: UUID) {
        unpublishProgress(for: id)
        guard let d = downloads.first(where: { $0.id == id }) else { return }
        if let gid = d.gid {
            Task { await rpc.removeDownload(gid: gid, status: d.status) }
        }
        removeFiles(for: d)
        downloads.removeAll { $0.id == id }
        persistence.save(downloads)
    }

    func setConnections(id: UUID, connections: Int) {
        guard let idx = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[idx].connections = connections
        persistence.save(downloads)
        if let gid = downloads[idx].gid {
            Task { await rpc.changeConnections(gid: gid, connections: connections) }
        }
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
        Task { await rpc.pauseAll() }
        for i in downloads.indices where downloads[i].status == .active {
            downloads[i].status = .paused
        }
        persistence.save(downloads)
    }

    func resumeAllDownloads() {
        Task { await rpc.resumeAll() }
        for i in downloads.indices where downloads[i].status == .paused || downloads[i].status == .waiting {
            downloads[i].status = .active
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

    private func removeFiles(for d: Download) {
        let dir = d.savePath ?? RPCConfig.defaultDownloadDir
        try? FileManager.default.removeItem(atPath: dir + "/" + d.filename + ".aria2desk")
    }

    private func clearSelected(deleteFiles: Bool = false) {
        let toDelete = downloads.filter { selectedDownloads.contains($0.id) }

        for d in toDelete {
            unpublishProgress(for: d.id)
            Task {
                if let gid = d.gid {
                    await rpc.removeDownload(gid: gid, status: d.status)
                }

                let dir = d.savePath ?? RPCConfig.defaultDownloadDir
                if deleteFiles, d.status == .completed {
                    try? FileManager.default.removeItem(atPath: dir + "/" + d.filename)
                }
                try? FileManager.default.removeItem(atPath: dir + "/" + d.filename + ".aria2desk")
            }
        }

        downloads.removeAll { selectedDownloads.contains($0.id) }
        selectedDownloads.removeAll()
        persistence.save(downloads)
    }
}
