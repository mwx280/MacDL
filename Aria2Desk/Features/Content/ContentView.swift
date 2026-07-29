import SwiftUI

struct ContentView: View {
    @State private var selected: SidebarItem? = .all

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
                LocalizedText(key: selected.titleKey)
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(LanguageManager.shared)
}
