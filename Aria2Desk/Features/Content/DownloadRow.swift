import SwiftUI

struct DownloadRow: View {
    let download: Download
    var onPause: ((UUID) -> Void)?
    var onResume: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onSetConnections: ((UUID, Int) -> Void)?
    var onShowInFinder: ((UUID) -> Void)?

    private let connectionOptions = [1, 2, 4, 8, 16, 32, 64]

    var body: some View {
        HStack(spacing: 12) {
            fileIcon
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(download.filename)
                    .lineLimit(1)
                    .truncationMode(.middle)

                ProgressView(value: download.progress)
                    .tint(progressTint)

                HStack(spacing: 16) {
                    statusLabel
                    if download.status == .active || download.status == .waiting {
                        Text(download.progress, format: .percent.precision(.fractionLength(1)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatSpeed(download.downloadSpeed))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(formatSize(download.downloadedSize) + " / " + formatSize(download.totalSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if download.status == .active {
                Button { onPause?(download.id) } label: { Label("Pause", systemImage: "pause") }
            }
            if download.status == .paused || download.status == .waiting {
                Button { onResume?(download.id) } label: { Label("Resume", systemImage: "play") }
            }
            Divider()
            Menu {
                ForEach(connectionOptions, id: \.self) { n in
                    let current = download.connections ?? SettingsStore.shared.maxConnections
                    Button { onSetConnections?(download.id, n) } label: {
                        if n == current {
                            Label("\(n) (\(LanguageManager.shared.localized("Current")))", systemImage: "checkmark")
                        } else {
                            Text("\(n)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "number")
                    let c = download.connections ?? SettingsStore.shared.maxConnections
                    Text("\(LanguageManager.shared.localized("Connections")): \(c)")
                }
            }
            Divider()
            Button { onShowInFinder?(download.id) } label: { Label("Show in Finder", systemImage: "folder") }
            Divider()
            Button { onDelete?(download.id) } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var fileIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: download.fileTypeIcon)
                .font(.title2)
                .foregroundStyle(download.fileTypeColor)
            statusBadge
        }
    }

    private var statusBadge: some View {
        ZStack {
            Circle()
                .fill(download.status.displayColor)
                .frame(width: 14, height: 14)
            Image(systemName: download.status.displayIcon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
        .offset(x: 6, y: 6)
    }

    @ViewBuilder
    private var statusLabel: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(download.status.displayColor)
                .frame(width: 6, height: 6)
            if download.status == .active && download.downloadSpeed > 0 {
                Text(formatSpeed(download.downloadSpeed))
                    .font(.caption)
                    .foregroundStyle(download.status.displayColor)
            } else {
                LocalizedText(key: download.status.labelKey)
                    .font(.caption)
                    .foregroundStyle(download.status.displayColor)
            }
        }
    }

    private var progressTint: Color {
        download.status == .active ? .blue : .secondary
    }
}
