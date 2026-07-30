import Foundation

@Observable
final class RPCTransport: RPCTransportProtocol {
    static let shared = RPCTransport(portAllocator: PortAllocator.shared)
    let portAllocator: PortAllocatorProtocol

    var status: RPCConnectionStatus = .disconnected
    var rpcPort = 0
    let config = RPCConfig()
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 10
        return URLSession(configuration: cfg)
    }()

    init(portAllocator: PortAllocatorProtocol) {
        self.portAllocator = portAllocator
    }

    // MARK: - Connection

    func testConnection() async -> Bool {
        status = .connecting
        defer {
            if status == .connecting { status = .disconnected }
        }
        guard let result: [String: Any] = await call(method: "aria2.getVersion"),
              result["version"] != nil
        else {
            status = .disconnected
            return false
        }
        status = .connected
        return true
    }

    func disconnect() {
        status = .disconnected
    }

    func autoConnect() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            _ = await testConnection()
        }
    }

    // MARK: - Download Operations

    func addUri(uri: String, options: [String: Any] = [:], position: Int? = nil) async -> String? {
        var params: [Any] = [[uri]]
        if !options.isEmpty { params.append(options) }
        if let position { params.append(position) }
        return await call(method: "aria2.addUri", params: params)
    }

    func tellActive() async -> [[String: Any]] {
        (await call(method: "aria2.tellActive")) ?? []
    }

    func tellWaiting(offset: Int = 0, num: Int = 100) async -> [[String: Any]] {
        (await call(method: "aria2.tellWaiting", params: [offset, num])) ?? []
    }

    func tellStopped(offset: Int = 0, num: Int = 100) async -> [[String: Any]] {
        (await call(method: "aria2.tellStopped", params: [offset, num])) ?? []
    }

    func pause(gid: String) async -> Bool {
        let result: String? = await call(method: "aria2.pause", params: [gid])
        return result == gid
    }

    func pauseAll() async -> Bool {
        let result: String? = await call(method: "aria2.pauseAll")
        return result == "OK"
    }

    func unpause(gid: String) async -> Bool {
        let result: String? = await call(method: "aria2.unpause", params: [gid])
        return result == gid
    }

    func unpauseAll() async -> Bool {
        let result: String? = await call(method: "aria2.unpauseAll")
        return result == "OK"
    }

    func remove(gid: String) async -> Bool {
        let result: String? = await call(method: "aria2.remove", params: [gid])
        return result == gid
    }

    func forceRemove(gid: String) async -> Bool {
        let result: String? = await call(method: "aria2.forceRemove", params: [gid])
        return result == gid
    }

    func getGlobalStat() async -> [String: Any]? {
        await call(method: "aria2.getGlobalStat")
    }

    func changeOption(gid: String, options: [String: Any]) async -> Bool {
        let result: String? = await call(method: "aria2.changeOption", params: [gid, options])
        return result == "OK"
    }

    // MARK: - Generic RPC Call

    private func call<T>(method: String, params: [Any] = []) async -> T? {
        guard rpcPort > 0 else { return nil }

        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": secretParams(params),
        ]

        guard let url = URL(string: "http://\(config.host):\(rpcPort)/jsonrpc"),
              let httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["error"] == nil,
                  let result = json["result"] as? T
            else { return nil }
            return result
        } catch {
            return nil
        }
    }

    private func secretParams(_ params: [Any]) -> [Any] {
        let token = SettingsStore.shared.secretToken.trimmingCharacters(in: .whitespaces)
        if token.isEmpty { return params }
        return ["token:\(token)"] + params
    }
}
