import SwiftUI
import AppKit

struct ContentView: View {
    @State private var model = ContentViewModel()
    @State private var selected: SidebarItem? = .all
    @State private var showNewDownloadSheet = false
    @State private var newDownloadURLs = ""
    @AppStorage("appearance") private var appearance: Appearance = .system

    private var sidebarIdealWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let maxWidth = SidebarItem.allCases.map { item -> CGFloat in
            let text = LanguageManager.shared.localized(item.titleKey)
            return (text as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 100
        return maxWidth + 56
    }

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
            .navigationSplitViewColumnWidth(min: 100, ideal: sidebarIdealWidth, max: 280)
        } detail: {
            if selected != nil { downloadsView }
        }
        .toolbar {
            ToolbarItemGroup {
                Picker(selection: Bindable(model).fileTypeFilter) {
                    ForEach(FileTypeFilter.allCases, id: \.self) { f in
                        Label(title: { LocalizedText(key: f.labelKey) }, icon: { Image(systemName: f.icon) })
                            .tag(f)
                    }
                } label: { }
                .labelsHidden()
                .frame(width: 60)
                .help("Filter")

                Spacer()

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

                Button { model.pauseAllDownloads() } label: { Label("Pause All", systemImage: "pause.rectangle") }
                    .disabled(!model.downloads.contains { $0.status == .active })
                    .help("Pause All")
                Button { model.resumeAllDownloads() } label: { Label("Resume All", systemImage: "play.rectangle") }
                    .disabled(!model.downloads.contains { $0.status == .paused || $0.status == .waiting })
                    .help("Resume All")
            }
        }
        .sheet(isPresented: $showNewDownloadSheet) {
            NewDownloadView(
                text: $newDownloadURLs,
                onDownload: { urls, path, connections, dlLimit, ulLimit in
                    for url in urls.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
                        model.addDownload(url: url, savePath: path, connections: connections, dlLimit: dlLimit, ulLimit: ulLimit)
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
            VStack(spacing: 12) {
                Image(systemName: "square.and.arrow.down")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                LocalizedText(key: "No Downloads")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            DownloadListView(downloads: f, selection: $model.selectedDownloads,
                onPause: { model.pauseDownload(id: $0) },
                onResume: { model.resumeDownload(id: $0) },
                onDelete: { id in model.selectedDownloads = [id]; model.confirmDelete() },
                onSetConnections: { model.setConnections(id: $0, connections: $1) },
                onSetDownloadLimit: { model.setDownloadLimit(id: $0, limit: $1) },
                onSetUploadLimit: { model.setUploadLimit(id: $0, limit: $1) },
                onShowInFinder: { id in
                    guard let d = model.downloads.first(where: { $0.id == id }) else { return }
                    let path = d.savePath ?? SettingsStore.shared.downloadPath
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                },
                onCopyURL: { id in
                    guard let d = model.downloads.first(where: { $0.id == id }), !d.url.isEmpty else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(d.url, forType: .string)
                }
            )
        }
    }
}

#Preview {
    ContentView()
        .environment(LanguageManager.shared)
        .environment(Aria2RPCClient.shared)
}
