import SwiftUI

struct DownloadRow: View {
    let download: Download
    var isMultiSelection: Bool = false
    var onPause: ((UUID) -> Void)?
    var onResume: ((UUID) -> Void)?
    var onRetry: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onSetDownloadLimit: ((UUID, Int) -> Void)?
    var onSetMaxChunks: ((UUID, Int) -> Void)?
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
                    resumeBadge
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
            if !isMultiSelection {
                speedMenu("arrow.down", onSetDownloadLimit, download.downloadLimit)
                if download.supportsResume == false {
                    Label {
                        Text(LanguageManager.shared.localized("Single connection · server does not support resume"))
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                    .foregroundStyle(.secondary)
                    .disabled(true)
                } else {
                    chunkMenu(onSetMaxChunks, download.maxConcurrentChunks)
                }
            }
            Divider()
            Button(action: { onCopyURL?(download.id) }) {
                Label(LanguageManager.shared.localized("Copy Link"), systemImage: "link")
            }
            if !isMultiSelection {
                Button(action: { onShowInFinder?(download.id) }) {
                    Label(LanguageManager.shared.localized("Show in Finder"), systemImage: "folder")
                }
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

    @ViewBuilder
    private var resumeBadge: some View {
        if let canResume = download.supportsResume,
           download.status == .active || download.status == .paused || download.status == .waiting {
            HStack(spacing: 3) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.caption2)
                Text(LanguageManager.shared.localized(canResume ? "Resumable" : "Not Resumable"))
                    .font(.caption)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((canResume ? Color.green : Color.red).opacity(0.15), in: Capsule())
            .foregroundStyle(canResume ? .green : .red)
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

    @ViewBuilder
    private func chunkMenu(_ action: ((UUID, Int) -> Void)?, _ current: Int) -> some View {
        let options = [1, 2, 4, 8]
        Menu {
            ForEach(options, id: \.self) { count in
                Button { action?(download.id, count) } label: {
                    if count == current {
                        Label("\(count)", systemImage: "checkmark")
                    } else {
                        Text("\(count)")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x2")
                Text("\(current) Threads")
            }
        }
    }
}

#Preview("下载任务") {
    List {
        DownloadRow(
            download: Download(
                filename: "ubuntu-24.04-desktop-amd64.iso",
                url: "https://releases.ubuntu.com/24.04/ubuntu-24.04-desktop-amd64.iso",
                totalSize: 6_100_000_000,
                downloadedSize: 2_800_000_000,
                downloadSpeed: 12_582_912,
                status: .active,
                downloadLimit: nil,
                maxConcurrentChunks: 8,
                supportsResume: true
            )
        )
    }
    .listStyle(.inset)
    .frame(width: 560, height: 80)
    .environment(LanguageManager.shared)
}

#Preview("下载任务（含路径）") {
    let d = Download(
        filename: "ubuntu-24.04-desktop-amd64.iso",
        url: "https://releases.ubuntu.com/24.04/ubuntu-24.04-desktop-amd64.iso",
        totalSize: 6_100_000_000,
        downloadedSize: 2_800_000_000,
        downloadSpeed: 12_582_912,
        status: .active,
        savePath: "/Users/xiaowu/Downloads",
        maxConcurrentChunks: 8,
        supportsResume: true
    )
    return VStack(spacing: 0) {
        List {
            DownloadRow(download: d)
            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text((d.savePath ?? AppConfig.defaultDownloadDir) + "/" + d.filename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .listStyle(.inset)
    }
    .frame(width: 560, height: 120)
    .environment(LanguageManager.shared)
}

#Preview("下载任务（重设计）") {
    let d = Download(
        filename: "ubuntu-24.04-desktop-amd64.iso",
        url: "https://releases.ubuntu.com/24.04/ubuntu-24.04-desktop-amd64.iso",
        totalSize: 6_100_000_000,
        downloadedSize: 2_800_000_000,
        downloadSpeed: 12_582_912,
        status: .active,
        savePath: "/Users/xiaowu/Downloads",
        maxConcurrentChunks: 8,
        supportsResume: true
    )
    let path = (d.savePath ?? AppConfig.defaultDownloadDir) + "/" + d.filename
    return VStack(spacing: 0) {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: d.fileTypeIcon)
                    .font(.title2)
                    .foregroundStyle(d.fileTypeColor)
                    .frame(width: 38, height: 38)
                Circle()
                    .fill(d.status.displayColor)
                    .frame(width: 14, height: 14)
                    .overlay {
                        Image(systemName: d.status.displayIcon)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 5, y: 5)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(d.filename)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(d.status.displayColor)
                                .frame(width: 6, height: 6)
                            Text(LanguageManager.shared.localized(d.status.labelKey))
                                .font(.caption)
                        }
                        .foregroundStyle(d.status.displayColor)
                        if let canResume = d.supportsResume {
                            Text(LanguageManager.shared.localized(canResume ? "Resumable" : "Not Resumable"))
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background((canResume ? Color.green : Color.red).opacity(0.15), in: Capsule())
                                .foregroundStyle(canResume ? .green : .red)
                        }
                    }
                }

                ProgressView(value: d.progress)
                    .tint(.blue)

                HStack(spacing: 6) {
                    Text(d.progress, format: .percent.precision(.fractionLength(1)))
                    Text(formatSpeed(d.downloadSpeed))
                    Spacer()
                    Text(formatSize(d.downloadedSize) + " / " + formatSize(d.totalSize))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "folder")
                        .font(.caption2)
                    Text(path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        Spacer()
    }
    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
    .frame(width: 560, height: 150)
    .environment(LanguageManager.shared)
}
