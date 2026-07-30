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
        get {
            if let token = defaults.string(forKey: "rpcSecretToken"), !token.isEmpty {
                return token
            }
            let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            defaults.set(token, forKey: "rpcSecretToken")
            return token
        }
        set { defaults.set(newValue, forKey: "rpcSecretToken") }
    }

    var downloadPath: String {
        get {
            defaults.string(forKey: "downloadPath") ?? NSHomeDirectory() + "/Downloads"
        }
        set { defaults.set(newValue, forKey: "downloadPath") }
    }

    var maxDownloadSpeed: Int {
        get { defaults.integer(forKey: "maxDownloadSpeed") }
        set { defaults.set(newValue, forKey: "maxDownloadSpeed") }
    }

    var maxUploadSpeed: Int {
        get { defaults.integer(forKey: "maxUploadSpeed") }
        set { defaults.set(newValue, forKey: "maxUploadSpeed") }
    }
}
