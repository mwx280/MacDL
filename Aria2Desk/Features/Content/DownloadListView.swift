import SwiftUI

struct DownloadListView: View {
    let downloads: [Download]

    var body: some View {
        List(downloads) { download in
            DownloadRow(download: download)
        }
        .listStyle(.inset)
    }
}

private struct DownloadRow: View {
    let download: Download

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
    }

    private var fileIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: fileTypeIcon)
                .font(.title2)
                .foregroundStyle(fileTypeColor)
            statusBadge
        }
    }

    private var fileTypeIcon: String {
        let ext = (download.filename as NSString).pathExtension.lowercased()
        if ext == "iso" { return "opticaldisc" }
        if ["mkv", "mp4", "avi", "mov", "wmv", "flv", "m4v"].contains(ext) { return "film" }
        if ["xip", "zip", "tar", "gz", "bz2", "7z", "rar"].contains(ext) { return "shippingbox" }
        if ["dmg", "pkg"].contains(ext) { return "app.dashed" }
        if ["gguf", "bin", "pt", "safetensors"].contains(ext) { return "cpu" }
        if ext == "pdf" { return "doc.richtext" }
        if ["txt", "md", "json", "xml", "yaml", "yml", "csv"].contains(ext) { return "doc.text" }
        if ["jpg", "jpeg", "png", "gif", "webp", "heic"].contains(ext) { return "photo" }
        if ["mp3", "flac", "wav", "aac"].contains(ext) { return "music.note" }
        return "doc"
    }

    private var fileTypeColor: Color {
        let ext = (download.filename as NSString).pathExtension.lowercased()
        if ext == "iso" { return .indigo }
        if ["mkv", "mp4", "avi", "mov"].contains(ext) { return .purple }
        if ["xip", "zip", "tar", "gz", "dmg"].contains(ext) { return .orange }
        if ["gguf", "bin", "pt"].contains(ext) { return .mint }
        if ext == "pdf" { return .red }
        if ["jpg", "jpeg", "png", "gif"].contains(ext) { return .blue }
        if ["mp3", "flac", "wav"].contains(ext) { return .pink }
        return .secondary
    }

    private var statusBadge: some View {
        ZStack {
            Circle()
                .fill(statusColor)
                .frame(width: 14, height: 14)
            Image(systemName: statusIcon)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
        .offset(x: 6, y: 6)
    }

    @ViewBuilder
    private var statusLabel: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
    }

    private var statusText: String {
        if download.status == .active {
            return download.downloadSpeed > 0 ? formatSpeed(download.downloadSpeed) : "Active"
        }
        if download.status == .paused { return "Paused" }
        if download.status == .waiting { return "Waiting" }
        if download.status == .completed { return "Completed" }
        if download.status == .stopped { return "Stopped" }
        return "Error"
    }

    private var statusIcon: String {
        if download.status == .active { return "arrow.down.circle.fill" }
        if download.status == .paused { return "pause.circle.fill" }
        if download.status == .waiting { return "clock.fill" }
        if download.status == .completed { return "checkmark.circle.fill" }
        if download.status == .stopped { return "stop.circle.fill" }
        return "exclamationmark.circle.fill"
    }

    private var statusColor: Color {
        if download.status == .active { return .blue }
        if download.status == .paused { return .orange }
        if download.status == .waiting { return .secondary }
        if download.status == .completed { return .green }
        if download.status == .stopped { return .gray }
        return .red
    }

    private var progressTint: Color {
        download.status == .active ? .blue : .secondary
    }

    private func formatSpeed(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes) + "/s"
    }

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}
