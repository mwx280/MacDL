import Foundation
import AppKit

// Checks the GitHub releases feed (preview channel only), downloads the DMG
// asset and installs it by mounting, replacing the running app and relaunching.
enum UpdateService {
    static let repo = "mwx280/MacDL"
    private static let releasesURL = URL(string: "https://api.github.com/repos/\(repo)/releases")!

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    struct Release: Decodable {
        let tagName: String
        let name: String?
        let publishedAt: String?
        let body: String?
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case publishedAt = "published_at"
            case body
            case prerelease
            case assets
        }
    }

    struct Asset: Decodable {
        let name: String
        let downloadURL: URL?
        let size: Int64?

        enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case size
        }
    }

    enum UpdateError: Swift.Error, LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case noRelease
        case noAsset
        case downloadFailed
        case mountFailed
        case appNotFound
        case installFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "The update server returned an invalid response."
            case .httpStatus(let code): return "The update server responded with HTTP \(code)."
            case .noRelease: return "No release is published yet."
            case .noAsset: return "The release has no downloadable package."
            case .downloadFailed: return "The update download failed."
            case .mountFailed: return "Could not mount the downloaded package. Try opening it in Finder instead."
            case .appNotFound: return "The update package does not contain MacDL."
            case .installFailed: return "Installing the update failed."
            }
        }
    }

    /// Fetches the newest release. `releases/latest` skips prereleases, and the
    /// preview channel is all prereleases, so the full list is used instead.
    static func latestRelease() async throws -> Release? {
        var req = URLRequest(url: releasesURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("MacDL", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw UpdateError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { return nil }
            throw UpdateError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode([Release].self, from: data).first
    }

    /// The best installable package for a release: prefer a .dmg asset.
    static func package(for release: Release) -> Asset? {
        release.assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }

    /// True when the release tag is newer than the running version.
    static func isNewer(_ release: Release, than current: String) -> Bool {
        compareVersions(release.tagName, current) > 0
    }

    static func compareVersions(_ a: String, _ b: String) -> Int {
        let av = numericComponents(a)
        let bv = numericComponents(b)
        for i in 0..<max(av.count, bv.count) {
            let x = i < av.count ? av[i] : 0
            let y = i < bv.count ? bv[i] : 0
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }

    private static func numericComponents(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .compactMap { Int($0) }
    }

    /// Downloads a release asset to the Downloads folder, reporting 0...1 progress.
    static func download(_ asset: Asset, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard let url = asset.downloadURL else { throw UpdateError.noAsset }
        let dir = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let destination = dir.appendingPathComponent(asset.name)
        let location = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Swift.Error>) in
            let downloader = UpdateDownloader(progress: progress) { result in
                Self.activeDownloaders.removeValue(forKey: url)
                cont.resume(with: result)
            }
            Self.activeDownloaders[url] = downloader
            downloader.start(url)
        }
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            throw UpdateError.downloadFailed
        }
        return destination
    }

    nonisolated(unsafe) private static var activeDownloaders: [URL: UpdateDownloader] = [:]

    /// Installs the downloaded DMG: mount it, replace the running app bundle and
    /// relaunch. Throws mountFailed when the sandbox blocks mounting; the caller
    /// can then offer to open the DMG in Finder for a manual install.
    @MainActor
    static func install(dmgURL: URL) async throws {
        let mountPoint = try await Task.detached(priority: .userInitiated) { try mount(dmgURL) }.value
        let mountedApp = mountPoint
            .appendingPathComponent("MacDL.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: mountedApp.path) else {
            throw UpdateError.appNotFound
        }
        let current = Bundle.main.bundleURL
        try replaceApp(from: mountedApp, to: current)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSWorkspace.shared.open(current)
            NSApp.terminate(nil)
        }
    }

    private nonisolated static func mount(_ dmgURL: URL) throws -> URL {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        proc.arguments = ["attach", "-nobrowse", "-noautoopen", "-plist", dmgURL.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { throw UpdateError.mountFailed }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = plist as? [String: Any],
              let entities = dict["system-entities"] as? [[String: Any]]
        else { throw UpdateError.mountFailed }
        guard let mountPath = entities.compactMap({ $0["mount-point"] as? String }).first,
              !mountPath.isEmpty
        else { throw UpdateError.mountFailed }
        return URL(fileURLWithPath: mountPath)
    }

    @MainActor
    private static func replaceApp(from newApp: URL, to current: URL) throws {
        let parent = current.deletingLastPathComponent()
        guard ensureWritable(parent) else { throw UpdateError.installFailed }
        try? FileManager.default.removeItem(at: current)
        do {
            try FileManager.default.copyItem(at: newApp, to: current)
        } catch {
            throw UpdateError.installFailed
        }
    }

    /// The sandbox only allows writing into a folder the user picked. Ask for the
    /// install location (normally /Applications) once when the target isn't writable.
    @MainActor
    private static func ensureWritable(_ dir: URL) -> Bool {
        if FileManager.default.isWritableFile(atPath: dir.path) { return true }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.message = LanguageManager.shared.localized("Select the folder containing MacDL to allow updating")
        panel.directoryURL = dir
        guard panel.runModal() == .OK, let selected = panel.url else { return false }
        let ok = selected.startAccessingSecurityScopedResource()
        defer { if ok { selected.stopAccessingSecurityScopedResource() } }
        return ok && FileManager.default.isWritableFile(atPath: selected.path)
    }
}

// URLSessionDownloadDelegate keeps the downloader alive until the session
// finishes; the caller also holds it in UpdateService.activeDownloaders.
private final class UpdateDownloader: NSObject, URLSessionDownloadDelegate {
    private let progress: (Double) -> Void
    private let completion: (Result<URL, Swift.Error>) -> Void
    private var session: URLSession?
    private var finished = false

    init(progress: @escaping @Sendable (Double) -> Void, completion: @escaping (Result<URL, Swift.Error>) -> Void) {
        self.progress = progress
        self.completion = completion
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func start(_ url: URL) {
        session?.downloadTask(with: url).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !finished else { return }
        finished = true
        completion(.success(location))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Swift.Error?) {
        guard !finished else { return }
        finished = true
        if let error {
            completion(.failure(error))
        }
    }
}
