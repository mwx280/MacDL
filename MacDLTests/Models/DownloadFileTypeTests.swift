import Testing
import Foundation
@testable import MacDL

@Suite struct DownloadFileTypeTests {
    @Test(arguments: [
        ("video.iso", "opticaldisc"),
        ("movie.mkv", "film"),
        ("archive.zip", "shippingbox"),
        ("app.dmg", "app.dashed"),
        ("model.gguf", "cpu"),
        ("doc.pdf", "doc.richtext"),
        ("notes.txt", "doc.text"),
        ("photo.jpg", "photo"),
        ("song.mp3", "music.note"),
        ("unknown.xyz", "doc"),
    ]) func fileTypeIcon(filename: String, expected: String) {
        let d = Download(id: UUID(), filename: filename, url: "", totalSize: 0, downloadedSize: 0, downloadSpeed: 0, status: .active, addedAt: Date())
        #expect(d.fileTypeIcon == expected)
    }

    @Test(arguments: [
        "video.iso", "movie.mkv", "archive.zip", "model.gguf", "doc.pdf", "unknown.xyz",
    ]) func fileTypeColorNotClear(filename: String) {
        let d = Download(id: UUID(), filename: filename, url: "", totalSize: 0, downloadedSize: 0, downloadSpeed: 0, status: .active, addedAt: Date())
        #expect(d.fileTypeColor != .clear)
    }
}
