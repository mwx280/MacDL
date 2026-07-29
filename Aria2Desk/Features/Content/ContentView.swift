import SwiftUI
import AppKit

struct ContentView: View {
    @State private var model = ContentViewModel()
    @State private var selected: SidebarItem? = .all
    @State private var showNewDownloadSheet = false
    @State private var newDownloadURLs = ""
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
            if selected != nil { downloadsView }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { newDownloadURLs = ""; showNewDownloadSheet = true } label: { Label("New Download", systemImage: "plus") }
                    .help("New Download")
                Button { model.pauseAll() } label: { Label("Pause", systemImage: "pause") }
                    .disabled(!model.downloads.contains { model.selectedDownloads.contains($0.id) && $0.status == .active })
                    .help("Pause")
                Button { model.resumeAll() } label: { Label("Resume", systemImage: "play") }
                    .disabled(!model.downloads.contains { model.selectedDownloads.contains($0.id) && ($0.status == .paused || $0.status == .waiting) })
                    .help("Resume")
                Button { model.confirmDelete() } label: { Label("Delete", systemImage: "trash") }
                    .disabled(model.selectedDownloads.isEmpty)
                    .help("Delete")
                Spacer()
                HStack(spacing: 6) {
                    Text(String(format: LanguageManager.shared.localized("Total %lld"), model.downloads.count))
                    Text("|").foregroundStyle(.tertiary)
                    Text(String(format: LanguageManager.shared.localized("Down %@"), formatSpeed(model.totalSpeed)))
                    Text("|").foregroundStyle(.tertiary)
                    Text(String(format: LanguageManager.shared.localized("Up %@"), formatSpeed(model.totalUpload)))
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
        }
        .sheet(isPresented: $showNewDownloadSheet) {
            NewDownloadView(
                text: $newDownloadURLs,
                onDownload: { urls in
                    for url in urls.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
                        model.addDownload(url: url)
                    }
                }
            )
        }
        .onChange(of: selected) { _, _ in model.selectedDownloads.removeAll() }
        .onChange(of: appearance) { _, new in new.apply() }
        .onAppear { appearance.apply() }
    }

    @ViewBuilder
    private var downloadsView: some View {
        let f = model.filteredDownloads(for: selected)
        if f.isEmpty {
            LocalizedText(key: "No Downloads")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
        } else {
            DownloadListView(downloads: f, selection: $model.selectedDownloads,
                onPause: { model.pauseDownload(id: $0) },
                onResume: { model.resumeDownload(id: $0) },
                onDelete: { model.deleteDownload(id: $0) }
            )
        }
    }
}

#Preview {
    ContentView()
        .environment(LanguageManager.shared)
        .environment(Aria2RPCClient.shared)
}
