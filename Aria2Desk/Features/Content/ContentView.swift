import SwiftUI
import AppKit

struct ContentView: View {
    @State private var selected: SidebarItem? = .all
    @State private var selectedDownloads = Set<UUID>()
    @State private var downloads = Download.mock
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
            detailView
        }
        .toolbar {
            ToolbarItemGroup {
                Button { newDownloadURLs = ""; showNewDownloadSheet = true } label: { Label("New Download", systemImage: "plus") }
                    .help("New Download")
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
        .sheet(isPresented: $showNewDownloadSheet) {
            NewDownloadView(
                text: $newDownloadURLs,
                onDownload: { urls in
                    for url in urls.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
                        let name = URL(string: url)?.lastPathComponent ?? "download-\(downloads.count + 1)"
                        let d = Download(id: UUID(), filename: name, url: url, totalSize: Int64.random(in: 1_000_000...100_000_000), downloadedSize: 0, downloadSpeed: Int64.random(in: 100_000...2_000_000), uploadSpeed: 0, status: .active, addedAt: Date())
                        downloads.append(d)
                    }
                }
            )
        }
        .onChange(of: selected) { _, _ in selectedDownloads.removeAll() }
        .onChange(of: appearance) { _, new in new.apply() }
        .onAppear { appearance.apply() }
    }

    private func pauseAll() {
        for id in selectedDownloads {
            guard let i = downloads.firstIndex(where: { $0.id == id }),
                  downloads[i].status == .active else { continue }
            downloads[i].status = .paused
        }
    }

    private func resumeAll() {
        for id in selectedDownloads {
            guard let i = downloads.firstIndex(where: { $0.id == id }),
                  downloads[i].status == .paused || downloads[i].status == .waiting else { continue }
            downloads[i].status = .active
        }
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

private struct NewDownloadView: View {
    @Binding var text: String
    let onDownload: (String) -> Void
    @State private var refresh = UUID()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.down")
                .font(.system(size: 32))
                .foregroundStyle(.tint)

            Text(LanguageManager.shared.localized("New Download"))
                .font(.headline)

            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .frame(height: 100)
                .overlay {
                    if text.isEmpty {
                        Text(LanguageManager.shared.localized("One URL per line, multiple URLs supported"))
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 12) {
                Button(LanguageManager.shared.localized("Cancel")) { dismiss() }
                    .keyboardShortcut(.escape)
                Button(LanguageManager.shared.localized("Download")) {
                    onDownload(text)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380, height: 260)
        .id(refresh)
        .onReceive(NotificationCenter.default.publisher(for: .languageChanged)) { _ in
            refresh = UUID()
        }
        .onAppear {
            guard text.isEmpty else { return }
            let pasteboard = NSPasteboard.general
            guard let str = pasteboard.string(forType: .string) else { return }
            let hasURL = str.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .contains { $0.lowercased().hasPrefix("http://") || $0.lowercased().hasPrefix("https://") }
            if hasURL { text = str }
        }
    }
}

#Preview {
    ContentView()
        .environment(LanguageManager.shared)
        .environment(Aria2RPCClient.shared)
}
