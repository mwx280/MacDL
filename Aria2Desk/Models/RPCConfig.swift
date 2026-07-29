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

    var color: String {
        switch self {
        case .disconnected: "red"
        case .connecting: "yellow"
        case .connected: "green"
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

    var baseURL: String {
        "http://\(host):\(port)/jsonrpc"
    }
}
