import SwiftUI

struct DownloadListView: View {
    let downloads: [Download]
    @Binding var selection: Set<UUID>

    var body: some View {
        List(downloads, selection: $selection) { download in
            DownloadRow(download: download)
        }
        .listStyle(.inset)
    }
}
