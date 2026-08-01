import Foundation

final class SettingsStore {
    static let shared = SettingsStore()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var maxConnections: Int {
        get {
            let v = defaults.integer(forKey: "maxConnections")
            return v == 0 ? 8 : v
        }
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
}
