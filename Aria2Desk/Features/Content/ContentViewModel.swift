import SwiftUI
import AppKit
import Observation

@Observable
final class ContentViewModel {
    var downloads: [Download]
    var selectedDownloads = Set<UUID>()
    var fileTypeFilter: FileTypeFilter = .all
    var isPolling = false

    private let rpc = Aria2RPCClient.shared
    private let persistence = DownloadPersistence.shared
    private var pollingTask: Task<Void, Never>?
    private var termObserver: NSObjectProtocol?

    init() {
        downloads = persistence.load()
        termObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.stopPolling()
            self.persistence.saveImmediately(self.downloads)
        }
        startPollingIfNeeded()
    }

    deinit {
        stopPolling()
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

    func startPollingIfNeeded() {
        guard !isPolling else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if rpc.isConnected {
                    await self.syncFromRPC()
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
        isPolling = true
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    private func syncFromRPC() async {
        let remoteDownloads = await rpc.fetchAllDownloads()
        if Task.isCancelled { return }

        var gidToUUID: [String: UUID] = [:]
        for d in downloads {
            if let gid = d.gid { gidToUUID[gid] = d.id }
        }

        var merged: [Download] = []
        var seenGIDs = Set<String>()

        for remote in remoteDownloads {
            guard let gid = remote.gid else { continue }
            seenGIDs.insert(gid)

            if let existingUUID = gidToUUID[gid],
               let idx = downloads.firstIndex(where: { $0.id == existingUUID })
            {
                var updated = downloads[idx]
                updated.totalSize = remote.totalSize
                updated.downloadedSize = remote.downloadedSize
                updated.downloadSpeed = remote.downloadSpeed
                updated.uploadSpeed = remote.uploadSpeed
                updated.status = remote.status
                if updated.filename == "unknown" || updated.filename.isEmpty {
                    updated.filename = remote.filename
                }
                merged.append(updated)
            } else {
                merged.append(remote)
            }
        }

        for d in downloads where d.status != .active || d.status != .waiting {
            if let gid = d.gid, !seenGIDs.contains(gid) {
                merged.append(d)
            }
        }

        for d in downloads where d.gid == nil {
            merged.append(d)
        }

        downloads = merged
        persistence.save(downloads)
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
            if let gid, let idx = downloads.firstIndex(where: { $0.id == d.id }) {
                downloads[idx].gid = gid
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
            persistence.save(downloads)
        }
    }

    func deleteDownload(id: UUID) {
        guard let d = downloads.first(where: { $0.id == id }) else { return }
        if let gid = d.gid {
            let isActive = d.status == .active
            Task { await rpc.removeDownload(gid: gid, force: isActive) }
        }
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
        let activeIds = downloads.filter { selectedDownloads.contains($0.id) && ($0.status == .active) }.map(\.id)
        for id in activeIds { pauseDownload(id: id) }
    }

    func resumeAll() {
        let pausedIds = downloads.filter { selectedDownloads.contains($0.id) && ($0.status == .paused || $0.status == .waiting) }.map(\.id)
        for id in pausedIds { resumeDownload(id: id) }
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
        cb.state = .off
        alert.accessoryView = cb

        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            clearCompleted(deleteFiles: cb.state == .on)
        }
    }

    private func clearCompleted(deleteFiles: Bool = false) {
        if deleteFiles {
            let dir = Aria2RPCClient.shared.config.downloadDirectory
            for d in downloads where selectedDownloads.contains(d.id) {
                try? FileManager.default.removeItem(atPath: dir + "/" + d.filename)
            }
        }
        for d in downloads where selectedDownloads.contains(d.id) {
            if let gid = d.gid {
                let isActive = d.status == .active
                Task { await rpc.removeDownload(gid: gid, force: isActive) }
            }
        }
        downloads.removeAll { selectedDownloads.contains($0.id) }
        selectedDownloads.removeAll()
        persistence.save(downloads)
    }
}
