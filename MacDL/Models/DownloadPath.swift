import Foundation

// Single place that derives the on-disk paths for a download (staging file
// while downloading, real file once done). Used by the view model and the
// engine coordinator so the ".macdl" convention can never drift.
enum DownloadPath {
    static func directory(for download: Download) -> String {
        download.savePath ?? AppConfig.defaultDownloadDir
    }

    static func staging(for download: Download) -> URL {
        URL(fileURLWithPath: directory(for: download) + "/" + download.filename + ".macdl")
    }

    static func destination(for download: Download) -> URL {
        URL(fileURLWithPath: directory(for: download) + "/" + download.filename)
    }
}
