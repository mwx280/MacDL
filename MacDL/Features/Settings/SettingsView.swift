import SwiftUI
import AppKit

struct SettingsView: View {
    private enum Pane: String, CaseIterable, Identifiable {
        case general
        case download
        case update
        case notifications

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "General"
            case .download: "Download"
            case .update: "Update"
            case .notifications: "Notifications"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .download: "arrow.down.circle"
            case .update: "arrow.triangle.2.circlepath"
            case .notifications: "bell"
            }
        }
    }

    @State private var pane: Pane = .general

    var body: some View {
        VStack(spacing: 0) {
            pillBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider()

            Group {
                switch pane {
                case .general: GeneralPane()
                case .download: DownloadPane()
                case .update: UpdatePane()
                case .notifications: NotificationsPane()
                }
            }
        }
        .frame(width: 520)
    }

    private var pillBar: some View {
        HStack(spacing: 4) {
            ForEach(Pane.allCases) { p in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { pane = p }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: p.icon)
                        LocalizedText(key: p.title)
                    }
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        pane == p ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear),
                        in: Capsule()
                    )
                    .foregroundStyle(pane == p ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.quaternary.opacity(0.5), in: Capsule())
    }
}

// Shared row-building helpers used by every settings pane.

func card(@ViewBuilder content: () -> some View) -> some View {
    VStack(spacing: 0) { content() }
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
}

func prefRow<C: View>(_ icon: String, _ label: String, description: String? = nil, suffix: String? = nil, @ViewBuilder control: () -> C) -> some View {
    HStack(spacing: 10) {
        Image(systemName: icon)
            .font(.body)
            .frame(width: 18)
            .foregroundStyle(.secondary)
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
