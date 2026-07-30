import SwiftUI

struct DownloadRow: View {
    let download: Download
    var onPause: ((UUID) -> Void)?
    var onResume: ((UUID) -> Void)?
    var onRetry: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onSetDownloadLimit: ((UUID, Int) -> Void)?
    var onShowInFinder: ((UUID) -> Void)?
    var onCopyURL: ((UUID) -> Void)?

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
                Button(action: { onPause?(download.id) }) {
                    Label(LanguageManager.shared.localized("Pause"), systemImage: "pause")
                }
            }
            if download.status == .paused || download.status == .waiting {
                Button(action: { onResume?(download.id) }) {
                    Label(LanguageManager.shared.localized("Resume"), systemImage: "play")
                }
            }
            if download.status == .error || download.status == .stopped {
                Button(action: { onRetry?(download.id) }) {
                    Label(LanguageManager.shared.localized("Retry"), systemImage: "arrow.clockwise")
                }
            }
            Divider()
            speedMenu("arrow.down", onSetDownloadLimit, download.downloadLimit)
            Divider()
            Button(action: { onCopyURL?(download.id) }) {
                Label(LanguageManager.shared.localized("Copy Link"), systemImage: "link")
            }
            Button(action: { onShowInFinder?(download.id) }) {
                Label(LanguageManager.shared.localized("Show in Finder"), systemImage: "folder")
            }
            Divider()
            Button(action: { onDelete?(download.id) }) {
                Label(LanguageManager.shared.localized("Delete"), systemImage: "trash")
            }
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
            if download.status == .error, let msg = download.errorMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(download.status.displayColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
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

    @ViewBuilder
    private func speedMenu(_ icon: String, _ action: ((UUID, Int) -> Void)?, _ current: Int?) -> some View {
        Menu {
            ForEach(speedOptions, id: \.self) { speed in
                Button { action?(download.id, speed) } label: {
                    if speed == (current ?? 0) {
                        Label(speedLabel(speed), systemImage: "checkmark")
                    } else {
                        Text(speedLabel(speed))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(speedLabel(current ?? 0))
            }
        }
    }

}
