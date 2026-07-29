import Foundation

final class DownloadPersistence {
    static let shared = DownloadPersistence()

    private static var fileURL: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.xiaowu.Aria2Desk")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("downloads.json")
    }

    private let queue = DispatchQueue(label: "com.xiaowu.save.downloads", qos: .utility)
    private var saveWorkItem: DispatchWorkItem?

    func load() -> [Download] {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let list = try? JSONDecoder().decode([Download].self, from: data)
        else { return PreviewContent.downloads }
        return list
    }

    func save(_ downloads: [Download]) {
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [downloads] in
            guard let data = try? JSONEncoder().encode(downloads) else { return }
            try? data.write(to: Self.fileURL, options: Data.WritingOptions.atomic)
        }
        saveWorkItem = item
        queue.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func saveImmediately(_ downloads: [Download]) {
        saveWorkItem?.cancel()
        guard let data = try? JSONEncoder().encode(downloads) else { return }
        try? data.write(to: Self.fileURL, options: Data.WritingOptions.atomic)
    }
}
