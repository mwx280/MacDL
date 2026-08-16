import Foundation
import MacDLCore

@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Per-download connection cap. `0` = Adaptive: the engine picks and adapts
    /// the connection count for best throughput (IDM-style).
    var maxConnections: Int {
        get { defaults.integer(forKey: "maxConnections") }
        set { defaults.set(newValue, forKey: "maxConnections") }
    }

    var maxConcurrentDownloads: Int {
        get {
            let v = defaults.integer(forKey: "maxConcurrentDownloads")
            return v == 0 ? 5 : v
        }
        set {
            defaults.set(newValue, forKey: "maxConcurrentDownloads")
            // Keep the engine's scheduler cap in sync with the setting.
            NotificationCenter.default.post(name: .maxConcurrentDownloadsChanged, object: nil)
        }
    }

    var downloadPath: String {
        get {
            defaults.string(forKey: "downloadPath") ?? AppConfig.defaultDownloadDir
        }
        set { defaults.set(newValue, forKey: "downloadPath") }
    }

    var downloadPathBookmark: Data? {
        get { defaults.data(forKey: "downloadPathBookmark") }
        set { defaults.set(newValue, forKey: "downloadPathBookmark") }
    }

    /// Global download speed cap shared by all tasks (bytes/second; 0 = unlimited).
    var maxDownloadSpeed: Int {
        get { defaults.integer(forKey: "maxDownloadSpeed") }
        set {
            defaults.set(newValue, forKey: "maxDownloadSpeed")
            // Keep the engine's shared bucket in sync so the aggregate throughput
            // across all downloads stays under the cap.
            ChunkDownloadTask.globalBucket.setRate(Double(newValue))
        }
    }

    var autoUpdate: Bool {
        get { defaults.object(forKey: "autoUpdate") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoUpdate") }
    }

    /// The release channel the updater follows. Unset means "follow the build":
    /// preview builds follow preview, stable builds follow stable.
    var updateChannel: UpdateChannel {
        get {
            if let raw = defaults.string(forKey: "updateChannel"),
               let channel = UpdateChannel(rawValue: raw) {
                return channel
            }
            return UpdateChannel.buildChannel
        }
        set { defaults.set(newValue.rawValue, forKey: "updateChannel") }
    }

    var notifyStart: Bool {
        get { defaults.object(forKey: "notifyStart") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyStart") }
    }

    var notifyCompleted: Bool {
        get { defaults.object(forKey: "notifyCompleted") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyCompleted") }
    }

    var notifyFailed: Bool {
        get { defaults.object(forKey: "notifyFailed") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyFailed") }
    }

    var notifyRedownload: Bool {
        get { defaults.object(forKey: "notifyRedownload") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyRedownload") }
    }

    var notifyLaunch: Bool {
        get { defaults.object(forKey: "notifyLaunch") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyLaunch") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launchAtLogin") }
        set { defaults.set(newValue, forKey: "launchAtLogin") }
    }

    var hideDockIconOnClose: Bool {
        get { defaults.bool(forKey: "hideDockIconOnClose") }
        set { defaults.set(newValue, forKey: "hideDockIconOnClose") }
    }

    /// Launch without showing the main window, keeping only the menu bar icon.
    var launchInBackground: Bool {
        get { defaults.object(forKey: "launchInBackground") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "launchInBackground") }
    }

    /// Resume tasks that were downloading when the app quit, on next launch.
    var autoResumeOnLaunch: Bool {
        get { defaults.object(forKey: "autoResumeOnLaunch") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "autoResumeOnLaunch") }
    }
}

extension Notification.Name {
    /// Posted when the global max-concurrent-downloads setting changes, so the
    /// engine's scheduler cap stays in sync.
    static let maxConcurrentDownloadsChanged = Notification.Name("com.xiaowu.maxConcurrentDownloadsChanged")
}
