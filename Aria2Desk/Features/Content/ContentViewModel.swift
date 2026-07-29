import SwiftUI
import AppKit
import Observation

@Observable
final class ContentViewModel {
    var downloads: [Download]
    var selectedDownloads = Set<UUID>()
    var fileTypeFilter: FileTypeFilter = .all

    private let persistence = DownloadPersistence.shared
    private var termObserver: NSObjectProtocol?

    init() {
        downloads = persistence.load()
        termObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.persistence.saveImmediately(self.downloads)
        }
    }

    deinit {
        if let observer = termObserver { NotificationCenter.default.removeObserver(observer) }
    }

    var totalSpeed: Int64 { downloads.reduce(0) { $0 + $1.downloadSpeed } }
    var totalUpload: Int64 { downloads.reduce(0) { $0 + $1.uploadSpeed } }

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

    func pauseAll() {
        for id in selectedDownloads {
            guard let i = downloads.firstIndex(where: { $0.id == id }),
                  downloads[i].status == .active else { continue }
            downloads[i].status = .paused
        }
        scheduleSave()
    }

    func resumeAll() {
        for id in selectedDownloads {
            guard let i = downloads.firstIndex(where: { $0.id == id }),
                  downloads[i].status == .paused || downloads[i].status == .waiting else { continue }
            downloads[i].status = .active
        }
        scheduleSave()
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
            clearCompleted(deleteFiles: cb.state == .on)
        }
    }

    func addDownload(url: String, savePath: String? = nil, connections: Int? = nil) {
        let name = URL(string: url)?.lastPathComponent ?? "download-\(downloads.count + 1)"
        let d = Download(
            id: UUID(),
            filename: name,
            url: url,
            totalSize: Int64.random(in: 1_000_000...100_000_000),
            downloadedSize: 0,
            downloadSpeed: Int64.random(in: 100_000...2_000_000),
            uploadSpeed: 0,
            status: .active,
            addedAt: Date(),
            savePath: savePath,
            connections: connections
        )
        downloads.append(d)
        scheduleSave()
    }

    func pauseDownload(id: UUID) {
        guard let i = downloads.firstIndex(where: { $0.id == id }),
              downloads[i].status == .active else { return }
        downloads[i].status = .paused
        scheduleSave()
    }

    func resumeDownload(id: UUID) {
        guard let i = downloads.firstIndex(where: { $0.id == id }),
              downloads[i].status == .paused || downloads[i].status == .waiting else { return }
        downloads[i].status = .active
        scheduleSave()
    }

    func deleteDownload(id: UUID) {
        downloads.removeAll { $0.id == id }
        scheduleSave()
    }

    func setConnections(id: UUID, connections: Int) {
        guard let i = downloads.firstIndex(where: { $0.id == id }) else { return }
        downloads[i].connections = connections
        scheduleSave()
    }

    func pauseAllDownloads() {
        for i in downloads.indices where downloads[i].status == .active {
            downloads[i].status = .paused
        }
        scheduleSave()
    }

    func resumeAllDownloads() {
        for i in downloads.indices where downloads[i].status == .paused || downloads[i].status == .waiting {
            downloads[i].status = .active
        }
        scheduleSave()
    }

    private func clearCompleted(deleteFiles: Bool = false) {
        if deleteFiles {
            let dir = Aria2RPCClient.shared.config.downloadDirectory
            for d in downloads where selectedDownloads.contains(d.id) {
                try? FileManager.default.removeItem(atPath: dir + "/" + d.filename)
            }
        }
        downloads.removeAll { selectedDownloads.contains($0.id) }
        selectedDownloads.removeAll()
        scheduleSave()
    }

    private func scheduleSave() {
        persistence.save(downloads)
    }
}
