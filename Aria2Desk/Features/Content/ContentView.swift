import SwiftUI

struct ContentView: View {
    @State private var selected: SidebarItem? = .all
    @State private var downloads = Download.mock

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
    }

    @ViewBuilder
    private var detailView: some View {
        if let selected {
            switch selected {
            case .settings:
                SettingsView()
            default:
                downloadsView
            }
        }
    }

    private var filteredDownloads: [Download] {
        switch selected {
        case .none, .settings: downloads
        case .all: downloads
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
            DownloadListView(downloads: filteredDownloads)
        }
    }
}

#Preview {
    ContentView()
        .environment(LanguageManager.shared)
}
