import SwiftUI
import MacDLCore

struct DownloadRow: View {
    let download: Download
    var isMultiSelection: Bool = false
    var canPrioritize: Bool = false
    var onPause: ((UUID) -> Void)?
    var onResume: ((UUID) -> Void)?
    var onRetry: ((UUID) -> Void)?
    var onRedownload: ((UUID) -> Void)?
    var onSetPriority: ((UUID) -> Void)?
    var onCancelPriority: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onSetDownloadLimit: ((UUID, Int) -> Void)?
    var onSetMaxChunks: ((UUID, Int) -> Void)?
    var onShowInFinder: ((UUID) -> Void)?
    var onCopyURL: ((UUID) -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            fileIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(download.filename)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    HStack(spacing: 8) {
                        if let canResume = download.supportsResume, download.status != .completed {
                            resumeGroup(canResume)
                        }
                        statusGroup
                    }
                }

                ProgressView(value: download.progress)
                    .tint(download.status == .active ? .blue : .secondary)

                HStack(spacing: 8) {
                    HStack(spacing: 3) {
                        Image(systemName: "gauge.with.dots.needle.50percent")
                            .font(.system(size: 9))
                        Text(download.progress, format: .percent.precision(.fractionLength(1)))
                    }
                    if download.status == .error, let msg = download.errorMessage {
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(download.status.displayColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if download.status == .active || download.status == .waiting {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 9))
                            Text(formatSpeed(download.downloadSpeed))
                        }
                        if let remaining = download.estimatedTimeRemaining {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 9))
                                Text(formatRemainingTime(remaining))
                            }
                        }
                    }
                    Spacer()
                    Text(formatSize(download.downloadedSize) + " / " + formatSize(download.totalSize))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
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
            if download.status == .completed {
                Button(action: { onRedownload?(download.id) }) {
                    Label(LanguageManager.shared.localized("Redownload"), systemImage: "arrow.down.circle")
                }
            }
            if canPrioritize, !isMultiSelection,
               download.isPriorityDownload != true,
               download.status == .active || download.status == .paused || download.status == .waiting {
                Button(action: { onSetPriority?(download.id) }) {
                    Label(LanguageManager.shared.localized("Priority Download"), systemImage: "arrow.up.circle")
                }
            }
            if download.isPriorityDownload == true, !isMultiSelection {
                Button(action: { onCancelPriority?(download.id) }) {
                    Label(LanguageManager.shared.localized("Cancel Priority Download"), systemImage: "arrow.down.circle")
                }
            }
            // Speed limit and thread settings only make sense while the download
            // can run; hide them for completed / failed entries.
            if [.active, .paused, .waiting].contains(download.status) {
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
            }
            Divider()
            if !isMultiSelection {
                Button(action: { onCopyURL?(download.id) }) {
                    Label(LanguageManager.shared.localized("Copy Link"), systemImage: "link")
                }
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
                .font(.title)
                .foregroundStyle(download.fileTypeColor)
            Circle()
                .fill(download.status.displayColor)
                .frame(width: 15, height: 15)
                .overlay {
                    Image(systemName: download.status.displayIcon)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                }
                .offset(x: 4, y: 4)
        }
    }

    @ViewBuilder
    private var statusGroup: some View {
        HStack(spacing: 3) {
            Image(systemName: download.status.displayIcon)
                .font(.caption2)
            Text(LanguageManager.shared.localized(download.status.labelKey))
                .font(.caption2)
        }
        .foregroundStyle(download.status.displayColor)
    }

    private func resumeGroup(_ canResume: Bool) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2)
            Text(LanguageManager.shared.localized(canResume ? "Resumable" : "Not Resumable"))
                .font(.caption2)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background((canResume ? Color.green : Color.red).opacity(0.15), in: Capsule())
        .foregroundStyle(canResume ? .green : .red)
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
                Text(String(format: LanguageManager.shared.localized("%lld Threads"), current))
            }
        }
    }
}
