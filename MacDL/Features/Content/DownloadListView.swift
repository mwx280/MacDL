import SwiftUI
import MacDLCore

struct DownloadListView: View {
    let downloads: [Download]
    @Binding var selection: Set<UUID>
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
        let priority = downloads.filter { $0.isPriorityDownload == true }
        let rest = downloads.filter { $0.isPriorityDownload != true }
        let canPrioritize = downloads.filter { [.active, .paused, .waiting].contains($0.status) }.count > 1
        List(selection: $selection) {
            if !priority.isEmpty {
                Section {
                    ForEach(priority) { row($0, canPrioritize: canPrioritize) }
                } header: {
                    priorityHeader(count: priority.count)
                }
                Section {
                    ForEach(rest) { row($0, canPrioritize: canPrioritize) }
                } header: {
                    queueHeader
                }
            } else {
                ForEach(downloads) { row($0, canPrioritize: canPrioritize) }
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func row(_ d: Download, canPrioritize: Bool) -> some View {
        DownloadRow(download: d,
            isMultiSelection: selection.count > 1,
            canPrioritize: canPrioritize,
            onPause: onPause, onResume: onResume, onRetry: onRetry,
            onRedownload: onRedownload,
            onSetPriority: onSetPriority,
            onCancelPriority: onCancelPriority,
            onDelete: onDelete,
            onSetDownloadLimit: onSetDownloadLimit,
            onSetMaxChunks: onSetMaxChunks,
            onShowInFinder: onShowInFinder, onCopyURL: onCopyURL)
    }

    private func priorityHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.caption)
                Text(LanguageManager.shared.localized("Priority Download"))
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.yellow)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.yellow.opacity(0.15), in: Capsule())
            Text("\(count)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var queueHeader: some View {
        Text(LanguageManager.shared.localized("In Queue"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
