import SwiftUI

struct DownloadListView: View {
    let downloads: [Download]
    @Binding var selection: Set<UUID>
    var onPause: ((UUID) -> Void)?
    var onResume: ((UUID) -> Void)?
    var onDelete: ((UUID) -> Void)?

    var body: some View {
        List(downloads, selection: $selection) { download in
            DownloadRow(download: download, onPause: onPause, onResume: onResume, onDelete: onDelete)
        }
        .listStyle(.inset)
    }
}
