import SwiftUI

struct DownloadListView: View {
    let downloads: [Download]

    private var totalCount: Int { downloads.count }
    private var activeCount: Int { downloads.filter { $0.status == .active }.count }
    private var totalDownloadSpeed: Int64 { downloads.reduce(0) { $0 + $1.downloadSpeed } }
    private var totalUploadSpeed: Int64 { downloads.reduce(0) { $0 + $1.uploadSpeed } }

    var body: some View {
        VStack(spacing: 0) {
            summaryBar
            List(downloads) { download in
                DownloadRow(download: download)
            }
            .listStyle(.inset)
        }
    }

    private var summaryBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.stack.3d.down.right")
                .foregroundStyle(.secondary)
                .imageScale(.small)
            Text("\(totalCount)")
                .foregroundStyle(.primary)
                .font(.system(size: 12, weight: .medium))

            if activeCount > 0 {
                Circle().fill(.blue).frame(width: 5, height: 5)
                Text("\(activeCount)")
                    .foregroundStyle(.blue)
                    .font(.system(size: 12))
            }

            Spacer()

            if totalDownloadSpeed > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                    Text(formatSpeed(totalDownloadSpeed))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
            }

            if totalUploadSpeed > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.up")
                        .foregroundStyle(.secondary)
                        .imageScale(.small)
                    Text(formatSpeed(totalUploadSpeed))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.fill.quaternary)
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
            if download.status == .active && download.downloadSpeed > 0 {
                Text(formatSpeed(download.downloadSpeed))
                    .font(.caption)
                    .foregroundStyle(statusColor)
            } else {
                LocalizedText(key: statusKey)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var statusKey: String {
        switch download.status {
        case .active: "Active"
        case .paused: "Paused"
        case .waiting: "Waiting"
        case .completed: "Completed"
        case .stopped: "Stopped"
        case .error: "Error"
        }
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

    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

private func formatSpeed(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    return formatter.string(fromByteCount: bytes) + "/s"
}
