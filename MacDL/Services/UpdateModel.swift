import Foundation
import Observation

// Shared update state so the app-launch auto-check and the Settings pane see
// the same status (e.g. a background download is already finished when the pane opens).
@Observable
final class UpdateModel {
    static let shared = UpdateModel()

    private let latestRelease: () async throws -> UpdateService.Release?
    private let downloadAsset: (UpdateService.Asset, @escaping (Double) -> Void) async throws -> URL
    private let installer: (URL) async throws -> Void

    init(latestRelease: @escaping () async throws -> UpdateService.Release? = { try await UpdateService.latestRelease() },
         downloadAsset: @escaping (UpdateService.Asset, @escaping (Double) -> Void) async throws -> URL = { asset, progress in
             try await UpdateService.download(asset, progress: progress)
         },
         installer: @escaping (URL) async throws -> Void = { try await UpdateService.install(dmgURL: $0) }) {
        self.latestRelease = latestRelease
        self.downloadAsset = downloadAsset
        self.installer = installer
    }

    enum Status {
        case idle
        case checking
        case upToDate
        case available(UpdateService.Release)
        case downloading(UpdateService.Release, Double)
        case downloaded(UpdateService.Release, URL)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var downloadedDMG: URL?

    func checkForUpdates() async {
        status = .checking
        do {
            guard let release = try await latestRelease() else {
                status = .upToDate
                return
            }
            if UpdateService.isNewer(release, than: UpdateService.currentVersion),
               UpdateService.package(for: release) != nil {
                status = .available(release)
            } else {
                status = .upToDate
            }
        } catch {
            status = .failed(LanguageManager.shared.localized("Update failed") + ": " + error.localizedDescription)
        }
    }

    func download(_ release: UpdateService.Release) async {
        guard let asset = UpdateService.package(for: release) else {
            status = .failed(LanguageManager.shared.localized("Update failed"))
            return
        }
        status = .downloading(release, 0)
        do {
            let url = try await downloadAsset(asset) { progress in
                DispatchQueue.main.async {
                    self.status = .downloading(release, progress)
                }
            }
            downloadedDMG = url
            status = .downloaded(release, url)
        } catch {
            status = .failed(LanguageManager.shared.localized("Update failed") + ": " + error.localizedDescription)
        }
    }

    func install(_ url: URL) async {
        do {
            try await installer(url)
        } catch {
            status = .failed(LanguageManager.shared.localized("Update failed") + ": " + error.localizedDescription)
        }
    }

    /// Runs once at launch when auto-update is enabled: check and download, but
    /// never install without the user clicking the install button.
    func autoCheckAndDownloadIfNeeded() {
        guard SettingsStore.shared.autoUpdate, case .idle = status else { return }
        Task {
            await checkForUpdates()
            if case .available(let release) = status {
                await download(release)
            }
        }
    }
}
