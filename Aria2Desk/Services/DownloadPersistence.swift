import Foundation
import os

final class DownloadPersistence {
    static let shared = DownloadPersistence()

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
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else { return [] }
        guard let list = try? JSONDecoder().decode([Download].self, from: data) else { return [] }
        return list
    }

    func save(_ downloads: [Download]) {
        write(downloads)
    }

    func saveImmediately(_ downloads: [Download]) {
        write(downloads)
    }

    private func write(_ downloads: [Download]) {
        let url = fileURL
        guard let data = try? JSONEncoder().encode(downloads) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
