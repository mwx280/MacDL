import Foundation

@MainActor
final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Per-download connection cap. `0` = Auto: the engine picks and adapts
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
        set { defaults.set(newValue, forKey: "maxConcurrentDownloads") }
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

    var maxDownloadSpeed: Int {
        get { defaults.integer(forKey: "maxDownloadSpeed") }
        set { defaults.set(newValue, forKey: "maxDownloadSpeed") }
    }

    var autoUpdate: Bool {
        get { defaults.object(forKey: "autoUpdate") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoUpdate") }
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
