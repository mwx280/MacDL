import Foundation

final class SettingsStore: SettingsStoreProtocol {
    static let shared = SettingsStore()

    private let defaults = UserDefaults.standard

    var appearance: Appearance {
        get {
            let raw = defaults.string(forKey: "appearance") ?? ""
            return Appearance(rawValue: raw) ?? .system
        }
        set { defaults.set(newValue.rawValue, forKey: "appearance") }
    }

    var maxConnections: Int {
        get {
            let v = defaults.integer(forKey: "maxConnections")
            return v == 0 ? 16 : v
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

    var secretToken: String {
        get { defaults.string(forKey: "rpcSecretToken") ?? "" }
        set { defaults.set(newValue, forKey: "rpcSecretToken") }
    }

    var downloadPath: String {
        get {
            defaults.string(forKey: "downloadPath") ?? NSHomeDirectory() + "/Downloads"
        }
        set { defaults.set(newValue, forKey: "downloadPath") }
    }
}
