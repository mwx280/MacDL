import SwiftUI
import AppKit
import Observation

@Observable
final class ContentViewModel {
    var downloads: [Download] = PreviewContent.downloads
    var selectedDownloads = Set<UUID>()

    var totalSpeed: Int64 { downloads.reduce(0) { $0 + $1.downloadSpeed } }
    var totalUpload: Int64 { downloads.reduce(0) { $0 + $1.uploadSpeed } }

    func filteredDownloads(for item: SidebarItem?) -> [Download] {
        switch item {
        case .none, .all: downloads
        case .active: downloads.filter { $0.status == .active }
        case .waiting: downloads.filter { $0.status == .waiting }
        case .completed: downloads.filter { $0.status == .completed }
        case .stopped: downloads.filter { $0.status == .stopped || $0.status == .error }
        }
    }

    func pauseAll() {
        for id in selectedDownloads {
            guard let i = downloads.firstIndex(where: { $0.id == id }),
                  downloads[i].status == .active else { continue }
            downloads[i].status = .paused
        }
    }

    func resumeAll() {
        for id in selectedDownloads {
            guard let i = downloads.firstIndex(where: { $0.id == id }),
                  downloads[i].status == .paused || downloads[i].status == .waiting else { continue }
            downloads[i].status = .active
        }
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

    func addDownload(url: String) {
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
            addedAt: Date()
        )
        downloads.append(d)
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
    }
}
