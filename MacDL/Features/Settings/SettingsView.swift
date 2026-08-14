import SwiftUI
import AppKit

struct SettingsView: View {
    private enum Pane: String {
        case general
        case download
        case update
        case notifications
    }

    @State private var pane: Pane = .general

    var body: some View {
        TabView(selection: $pane) {
            NotificationsPane()
                .tabItem {
                    Label(title: { LocalizedText(key: "Notifications") }, icon: { Image(systemName: "bell") })
                }
                .tag(Pane.notifications)

            GeneralPane()
                .tabItem {
                    Label(title: { LocalizedText(key: "General") }, icon: { Image(systemName: "gear") })
                }
                .tag(Pane.general)

            DownloadPane()
                .tabItem {
                    Label(title: { LocalizedText(key: "Download") }, icon: { Image(systemName: "arrow.down.circle") })
                }
                .tag(Pane.download)

            UpdatePane()
                .tabItem {
                    Label(title: { LocalizedText(key: "Update") }, icon: { Image(systemName: "arrow.triangle.2.circlepath") })
                }
                .tag(Pane.update)
        }
        .frame(width: 420, height: height(for: pane))
    }

    private func height(for pane: Pane) -> CGFloat {
        switch pane {
        case .general: 225
        case .download: 300
        case .update: 120
        case .notifications: 230
        }
    }
}

// Shared row-building helpers used by every settings pane.

func card(@ViewBuilder content: () -> some View) -> some View {
    VStack(spacing: 0) { content() }
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
}

func prefRow<C: View>(_ icon: String, _ label: String, suffix: String? = nil, @ViewBuilder control: () -> C) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .font(.body)
            .frame(width: 18)
            .foregroundStyle(.secondary)
        HStack(spacing: 5) {
            LocalizedText(key: label)
                .font(.body)
            if let suffix {
                LocalizedText(key: suffix)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        Spacer()
        control()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
}

var divider: some View { Divider().padding(.leading, 42) }
