import Foundation
import MacDLCore

final class DownloadPersistence {
    static let shared: DownloadPersistence = {
        let p = DownloadPersistence()
        p.migrateFromCaches()
        return p
    }()

    private let queue = DispatchQueue(label: "com.xiaowu.persistence", qos: .utility)

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else if ProcessInfo.isRunningTests {
            self.fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("com.xiaowu.MacDL-tests")
                .appendingPathComponent("downloads.json")
        } else {
            self.fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("com.xiaowu.MacDL")
                .appendingPathComponent("downloads.json")
        }
    }

    /// Maps a persisted (English) error message to its catalog key so legacy
    /// entries — saved before errorKey existed — can be re-localized at display
    /// time instead of showing a stale language.
    private static let legacyErrorKeyMap: [String: String] = [
        "Download file has been deleted": "Download file has been deleted",
        "Invalid URL": "Invalid URL",
        "Cancelled": "Cancelled",
        "Unknown error": "Unknown error",
        "Server does not support this download range": "Server does not support this download range",
        "File changed on server, resume not possible": "File changed on server, resume not possible",
        "Download folder access lost. Choose it again in Settings.": "Download folder access lost. Choose it again in Settings.",
    ]

    func load() -> [Download] {
        queue.sync {
            let url = fileURL
            guard let data = try? Data(contentsOf: url),
                  var list = try? JSONDecoder().decode([Download].self, from: data)
            else { return [] }
            for i in list.indices where list[i].errorKey == nil {
                if let msg = list[i].errorMessage,
                   let key = Self.legacyErrorKeyMap[msg] {
                    list[i].errorKey = key
                }
            }
            return list
        }
    }

    func save(_ downloads: [Download], caller: String = #function) {
        // Write on a background queue so encoding + I/O don't stall the main thread
        queue.async { self.write(downloads, caller: caller) }
    }

    func saveImmediately(_ downloads: [Download], caller: String = #function) {
        // Write synchronously (must-complete cases like quitting)
        queue.sync { self.write(downloads, caller: caller) }
    }

    private func migrateFromCaches() {
        let old = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.xiaowu.MacDL/downloads.json")
        let new = fileURL
        guard FileManager.default.fileExists(atPath: old.path),
              !FileManager.default.fileExists(atPath: new.path)
        else { return }
        try? FileManager.default.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.moveItem(at: old, to: new)
    }

    private func write(_ downloads: [Download], caller: String = "?") {
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(downloads) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
