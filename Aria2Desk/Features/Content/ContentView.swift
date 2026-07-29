import SwiftUI
import AppKit

struct ContentView: View {
    @State private var selected: SidebarItem? = .all
    @State private var selectedDownloads = Set<UUID>()
    @State private var downloads = Download.mock
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, id: \.self, selection: $selected) { item in
                Label {
                    LocalizedText(key: item.titleKey)
                } icon: {
                    Image(systemName: item.icon)
                }
            }
            .listStyle(.sidebar)
        } detail: {
            detailView
        }
        .toolbar {
            ToolbarItemGroup {
                Button { addDownload() } label: { Label("Add", systemImage: "plus") }
                    .help("Add")
                Button { pauseAll() } label: { Label("Pause", systemImage: "pause") }
                    .disabled(!downloads.contains { selectedDownloads.contains($0.id) && $0.status == .active })
                    .help("Pause")
                Button { resumeAll() } label: { Label("Resume", systemImage: "play") }
                    .disabled(!downloads.contains { selectedDownloads.contains($0.id) && ($0.status == .paused || $0.status == .waiting) })
                    .help("Resume")
                Button { confirmDelete() } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selectedDownloads.isEmpty)
                    .help("Delete")
                Spacer()
                HStack(spacing: 6) {
                    Text(String(format: LanguageManager.shared.localized("Total %lld"), downloads.count))
                    Text("|").foregroundStyle(.tertiary)
                    Text(String(format: LanguageManager.shared.localized("Down %@"), formatSpeed(downloads.reduce(0) { $0 + $1.downloadSpeed })))
                    Text("|").foregroundStyle(.tertiary)
                    Text(String(format: LanguageManager.shared.localized("Up %@"), formatSpeed(downloads.reduce(0) { $0 + $1.uploadSpeed })))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
        }
        .onChange(of: selected) { _, _ in selectedDownloads.removeAll() }
        .onChange(of: appearance) { _, new in new.apply() }
        .onAppear { appearance.apply() }
    }

    private func formatSpeed(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        return f.string(fromByteCount: bytes) + "/s"
    }

    private func pauseAll() {
        for id in selectedDownloads {
            guard let i = downloads.firstIndex(where: { $0.id == id }),
                  downloads[i].status == .active else { continue }
            downloads[i].status = .paused
        }
        selectedDownloads.removeAll()
    }

    private func resumeAll() {
        for id in selectedDownloads {
            guard let i = downloads.firstIndex(where: { $0.id == id }),
                  downloads[i].status == .paused || downloads[i].status == .waiting else { continue }
            downloads[i].status = .active
        }
        selectedDownloads.removeAll()
    }

    private func confirmDelete() {
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

    private func addDownload() {
        let new = Download(
            id: UUID(),
            filename: "new-download-\(downloads.count + 1).zip",
            url: "https://example.com/download\(downloads.count + 1).zip",
            totalSize: Int64.random(in: 1_000_000...100_000_000),
            downloadedSize: 0,
            downloadSpeed: Int64.random(in: 100_000...2_000_000),
            uploadSpeed: 0,
            status: .active,
            addedAt: Date()
        )
        downloads.append(new)
    }

    @ViewBuilder
    private var detailView: some View {
        if selected != nil { downloadsView }
    }

    private var filteredDownloads: [Download] {
        switch selected {
        case .none, .all: downloads
        case .active: downloads.filter { $0.status == .active }
        case .waiting: downloads.filter { $0.status == .waiting }
        case .completed: downloads.filter { $0.status == .completed }
        case .stopped: downloads.filter { $0.status == .stopped || $0.status == .error }
        }
    }

    @ViewBuilder
    private var downloadsView: some View {
        if filteredDownloads.isEmpty {
            LocalizedText(key: "No Downloads")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        } else {
            DownloadListView(downloads: filteredDownloads, selection: $selectedDownloads)
        }
    }
}

#Preview {
    ContentView()
        .environment(LanguageManager.shared)
        .environment(Aria2RPCClient.shared)
}
