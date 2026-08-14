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
            GeneralPane()
                .tabItem {
                    Label(title: { LocalizedText(key: "General") }, icon: { Image(systemName: "gearshape") })
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

            NotificationsPane()
                .tabItem {
                    Label(title: { LocalizedText(key: "Notifications") }, icon: { Image(systemName: "bell") })
                }
                .tag(Pane.notifications)
        }
        .frame(width: 520, height: height(for: pane))
    }

    private func height(for pane: Pane) -> CGFloat {
        switch pane {
        case .general: 290
        case .download: 390
        case .update: 170
        case .notifications: 285
        }
    }
}

// Shared row-building helpers used by every settings pane.

func card(@ViewBuilder content: () -> some View) -> some View {
    VStack(spacing: 0) { content() }
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
}

func prefRow<C: View>(_ icon: String, _ label: String, description: String? = nil, suffix: String? = nil, color: Color = .secondary, @ViewBuilder control: () -> C) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .font(.body)
            .frame(width: 18)
            .foregroundStyle(color)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                LocalizedText(key: label)
                    .font(.body)
                if let suffix {
                    LocalizedText(key: suffix)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if let description {
                LocalizedText(key: description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Spacer()
        control()
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 9)
}

var divider: some View { Divider().padding(.leading, 42) }
