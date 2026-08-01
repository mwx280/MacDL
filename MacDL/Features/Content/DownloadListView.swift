import SwiftUI

struct DownloadListView: View {
    let downloads: [Download]
    @Binding var selection: Set<UUID>
    var onPause: ((UUID) -> Void)?
    var onResume: ((UUID) -> Void)?
    var onRetry: ((UUID) -> Void)?
    var onSetPriority: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onSetDownloadLimit: ((UUID, Int) -> Void)?
    var onSetMaxChunks: ((UUID, Int) -> Void)?
    var onShowInFinder: ((UUID) -> Void)?
    var onCopyURL: ((UUID) -> Void)?

    var body: some View {
        let activeCount = downloads.filter { $0.status == .active }.count
        List(downloads, selection: $selection) { download in
            DownloadRow(download: download,
                isMultiSelection: selection.count > 1,
                canPrioritize: activeCount > 1,
                onPause: onPause, onResume: onResume, onRetry: onRetry,
                onSetPriority: onSetPriority,
                onDelete: onDelete,
                onSetDownloadLimit: onSetDownloadLimit,
                onSetMaxChunks: onSetMaxChunks,
                onShowInFinder: onShowInFinder, onCopyURL: onCopyURL)
        }
        .listStyle(.inset)
    }
}
