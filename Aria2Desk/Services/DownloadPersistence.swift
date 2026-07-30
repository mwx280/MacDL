import Foundation
import os

final class DownloadPersistence {
    static let shared = DownloadPersistence()

    static var persistedFileURL: URL { fileURL }

    private static var fileURL: URL {
        let base: URL
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            base = FileManager.default.temporaryDirectory
                .appendingPathComponent("com.xiaowu.Aria2Desk-tests")
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.xiaowu.Aria2Desk")
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("downloads.json")
    }

    func load() -> [Download] {
        let url = Self.fileURL
        guard let data = try? Data(contentsOf: url) else {
            os_log("[Persistence] no file at %@", url.path)
            return []
        }
        guard let list = try? JSONDecoder().decode([Download].self, from: data) else {
            os_log("[Persistence] decode failed at %@", url.path)
            return []
        }
        os_log("[Persistence] loaded %d downloads", list.count)
        return list
    }

    func save(_ downloads: [Download]) {
        write(downloads)
    }

    func saveImmediately(_ downloads: [Download]) {
        write(downloads)
    }

    private func write(_ downloads: [Download]) {
        let url = Self.fileURL
        do {
            let data = try JSONEncoder().encode(downloads)
            try data.write(to: url, options: .atomic)
            os_log("[Persistence] saved %d downloads to %@", downloads.count, url.path)
        } catch {
            os_log("[Persistence] save error: %@", error.localizedDescription)
        }
    }
}
