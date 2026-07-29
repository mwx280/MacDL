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
    var host: String {
        get { UserDefaults.standard.string(forKey: "rpcHost") ?? "localhost" }
        set { UserDefaults.standard.set(newValue, forKey: "rpcHost") }
    }

    var port: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "rpcPort")
            return v == 0 ? 6800 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "rpcPort") }
    }

    var secretToken: String {
        get { UserDefaults.standard.string(forKey: "rpcSecretToken") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "rpcSecretToken") }
    }

    var maxConnections: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "maxConnections")
            return v == 0 ? 16 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "maxConnections") }
    }

    var maxConcurrentDownloads: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: "maxConcurrentDownloads")
            return v == 0 ? 5 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: "maxConcurrentDownloads") }
    }

    var baseURL: String {
        "http://\(host):\(port)/jsonrpc"
    }

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
}
