struct AppearanceSettings {
    var appearance: Appearance
    var maxConnections: Int
    var maxConcurrentDownloads: Int
    var secretToken: String
}

protocol SettingsStoreProtocol {
    var appearance: Appearance { get set }
    var maxConnections: Int { get set }
    var maxConcurrentDownloads: Int { get set }
    var secretToken: String { get set }
    var downloadPath: String { get set }
    var maxDownloadSpeed: Int { get set }
}
