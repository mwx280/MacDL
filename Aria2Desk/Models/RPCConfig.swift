import Foundation

enum RPCConnectionStatus {
    case disconnected
    case connecting
    case connected

    var icon: String {
        switch self {
        case .disconnected: "circle.fill"
        case .connecting: "circle.dashed"
        case .connected: "circle.fill"
        }
    }
}

struct RPCConfig {
    var host: String = "localhost"

    var appSupportDirectory: String {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.xiaowu.Aria2Desk")
        return base.path
    }

    var aria2SessionPath: String {
        appSupportDirectory + "/aria2.session"
    }

    var downloadDirectory: String {
        appSupportDirectory + "/downloads"
    }

    var stagingDirectory: String {
        appSupportDirectory + "/.staging"
    }
}
