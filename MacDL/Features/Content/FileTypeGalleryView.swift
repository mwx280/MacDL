import SwiftUI

struct FileTypeGalleryView: View {
    private let extensions: [String] = [
        "iso",
        "mkv", "mp4", "avi", "mov", "wmv", "flv", "m4v",
        "xip", "zip", "tar", "gz", "bz2", "7z", "rar",
        "dmg", "pkg", "exe",
        "gguf", "bin", "pt", "safetensors",
        "pdf",
        "txt", "md", "json", "xml", "yaml", "yml", "csv",
        "jpg", "jpeg", "png", "gif", "webp", "heic",
        "mp3", "flac", "wav", "aac",
        "unknown",
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 12)], spacing: 12) {
                ForEach(extensions, id: \.self) { ext in
                    card(for: ext)
                }
            }
            .padding(16)
        }
        .frame(width: 600, height: 760)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func card(for ext: String) -> some View {
        let download = Download(filename: "sample.\(ext)", url: "", status: .completed)
        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: download.fileTypeIcon)
                    .font(.system(size: 28))
                    .foregroundStyle(download.fileTypeColor)
                    .frame(width: 44, height: 44)
                statusBadge
            }

            Text(ext)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)

            Text(download.fileTypeIcon)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusBadge: some View {
        ZStack {
            Circle()
                .fill(Color.green)
                .frame(width: 14, height: 14)
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white)
        }
        .offset(x: 6, y: 6)
    }
}

#Preview("File Type Gallery") {
    FileTypeGalleryView()
}
