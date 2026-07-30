import Foundation

final class DownloadPersistence {
    static let shared = DownloadPersistence()

    private let queue = DispatchQueue(label: "com.xiaowu.persistence", qos: .utility)

    private var fileURL: URL {
        let base: URL
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            base = FileManager.default.temporaryDirectory
                .appendingPathComponent("com.xiaowu.Aria2Desk-tests")
        } else {
            base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                .appendingPathComponent("com.xiaowu.Aria2Desk")
        }
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("downloads.json")
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

    func save(_ downloads: [Download]) {
        queue.async { [downloads] in
            let url = self.fileURL
            guard let data = try? JSONEncoder().encode(downloads) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    func saveImmediately(_ downloads: [Download]) {
        queue.sync {
            let url = fileURL
            guard let data = try? JSONEncoder().encode(downloads) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}
