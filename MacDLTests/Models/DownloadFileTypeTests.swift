import Testing
import Foundation
@testable import MacDL

@Suite struct DownloadFileTypeTests {
    @Test(arguments: [
        ("video.iso", "opticaldisc"),
        ("movie.mkv", "film"),
        ("video.webm", "film"),
        ("archive.zip", "shippingbox"),
        ("app.dmg", "app.dashed"),
        ("app.apk", "app.dashed"),
        ("setup.exe", "pc"),
        ("installer.msi", "pc"),
        ("model.gguf", "cpu"),
        ("model.onnx", "cpu"),
        ("doc.pdf", "doc.richtext"),
        ("doc.docx", "doc.richtext"),
        ("notes.txt", "doc.text"),
        ("script.py", "curlybraces"),
        ("page.html", "curlybraces"),
        ("style.css", "curlybraces"),
        ("app.swift", "curlybraces"),
        ("main.rs", "curlybraces"),
        ("util.c", "curlybraces"),
        ("app.java", "curlybraces"),
        ("gem.rb", "curlybraces"),
        ("index.php", "curlybraces"),
        ("query.sql", "curlybraces"),
        ("run.sh", "terminal"),
        ("font.ttf", "textformat"),
        ("photo.jpg", "photo"),
        ("img.svg", "photo"),
        ("song.mp3", "music.note"),
        ("song.m4a", "music.note"),
        ("disk.img", "externaldrive"),
        ("file.torrent", "arrow.down.doc"),
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
