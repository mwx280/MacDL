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
                Button { pauseAll() } label: { Label("Pause All", systemImage: "pause") }
                Button { resumeAll() } label: { Label("Resume All", systemImage: "play") }
                Button { clearCompleted() } label: { Label("Clear", systemImage: "trash") }
                Spacer()
                Text(String(format: LanguageManager.shared.localized("Total %lld"), downloads.count))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
                Divider().frame(height: 12)
                Text(String(format: LanguageManager.shared.localized("Down %@"), formatSpeed(downloads.reduce(0) { $0 + $1.downloadSpeed })))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                Divider().frame(height: 12)
                Text(String(format: LanguageManager.shared.localized("Up %@"), formatSpeed(downloads.reduce(0) { $0 + $1.uploadSpeed })))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
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
        for i in downloads.indices where downloads[i].status == .active {
            downloads[i].status = .paused
        }
    }

    private func resumeAll() {
        for i in downloads.indices where downloads[i].status == .paused || downloads[i].status == .waiting {
            downloads[i].status = .active
        }
    }

    private func clearCompleted() {
        downloads.removeAll { $0.status == .completed || $0.status == .stopped || $0.status == .error }
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
