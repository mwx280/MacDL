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
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            self.fileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("com.xiaowu.MacDL-tests")
                .appendingPathComponent("downloads.json")
        } else {
            self.fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("com.xiaowu.MacDL")
                .appendingPathComponent("downloads.json")
        }
    }

    func load() -> [Download] {
        queue.sync {
            let url = fileURL
            guard let data = try? Data(contentsOf: url),
                  let list = try? JSONDecoder().decode([Download].self, from: data)
            else { return [] }
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
