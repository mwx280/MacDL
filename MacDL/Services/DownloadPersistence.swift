import Foundation

final class DownloadPersistence {
    static let shared: DownloadPersistence = {
        let p = DownloadPersistence()
        p.migrateFromCaches()
        return p
    }()

    private let queue = DispatchQueue(label: "com.xiaowu.persistence", qos: .utility)

    private var fileURL: URL {
        let base: URL
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            base = FileManager.default.temporaryDirectory
                .appendingPathComponent("com.xiaowu.MacDL-tests")
        } else {
            base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("com.xiaowu.MacDL")
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("downloads.json")
    }

    func load() -> [Download] {
        queue.sync {
            let url = fileURL
            guard let data = try? Data(contentsOf: url),
                  let list = try? JSONDecoder().decode([Download].self, from: data)
            else { print("📖 load: no file or decode failed at \(url.path)"); return [] }
            print("📖 load: \(list.count) downloads, file=\(list.first?.filename ?? "nil") ts=\(list.first?.totalSize ?? -1) ds=\(list.first?.downloadedSize ?? -1)")
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
        guard let data = try? JSONEncoder().encode(downloads) else { print("❌ write: encode failed"); return }
        try? data.write(to: url, options: .atomic)
        print("📝 save: count=\(downloads.count) file=\(downloads.first?.filename ?? "nil") ts=\(downloads.first?.totalSize ?? -1) ds=\(downloads.first?.downloadedSize ?? -1) caller=\(caller)")
    }
}
