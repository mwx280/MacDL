import Foundation
import os

final class DownloadPersistence {
    static let shared = DownloadPersistence()

    private let defaults = UserDefaults.standard
    private var key: String {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ? "downloads_test" : "downloads_v2"
    }

    func load() -> [Download] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([Download].self, from: data)
        else {
            os_log("[Persistence] no data in UserDefaults")
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
        do {
            let data = try JSONEncoder().encode(downloads)
            defaults.set(data, forKey: key)
            os_log("[Persistence] saved %d downloads", downloads.count)
        } catch {
            os_log("[Persistence] save error: %@", error.localizedDescription)
        }
    }
}
