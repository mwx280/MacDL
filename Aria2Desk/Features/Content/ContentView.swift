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
            DownloadListView(downloads: f, selection: $model.selectedDownloads)
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
