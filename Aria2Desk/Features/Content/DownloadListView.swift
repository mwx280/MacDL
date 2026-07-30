import SwiftUI

struct DownloadListView: View {
    let downloads: [Download]
    @Binding var selection: Set<UUID>
    var onPause: ((UUID) -> Void)?
    var onResume: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?
    var onSetConnections: ((UUID, Int) -> Void)?
    var onSetDownloadLimit: ((UUID, Int) -> Void)?
    var onSetUploadLimit: ((UUID, Int) -> Void)?
    var onShowInFinder: ((UUID) -> Void)?
    var onCopyURL: ((UUID) -> Void)?

    var body: some View {
        List(downloads, selection: $selection) { download in
            DownloadRow(download: download,
                onPause: onPause, onResume: onResume,
                onDelete: onDelete, onSetConnections: onSetConnections,
                onSetDownloadLimit: onSetDownloadLimit, onSetUploadLimit: onSetUploadLimit,
                onShowInFinder: onShowInFinder, onCopyURL: onCopyURL)
        }
        .listStyle(.inset)
    }
}
