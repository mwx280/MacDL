import Foundation

@Observable
final class RPCTransport: RPCTransportProtocol {
    static let shared = RPCTransport(portAllocator: PortAllocator.shared)
    let portAllocator: PortAllocatorProtocol

    var status: RPCConnectionStatus = .disconnected
    var rpcPort = 0
    let config = RPCConfig()

    init(portAllocator: PortAllocatorProtocol) {
        self.portAllocator = portAllocator
    }

    func testConnection() async -> Bool {
        status = .connecting
        defer {
            if status == .connecting { status = .disconnected }
        }

        let requestBody: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": "aria2.getVersion",
            "params": secretParams([]),
        ]

        guard let url = URL(string: "http://\(config.host):\(rpcPort)/jsonrpc"),
              let httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        else {
            status = .disconnected
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  json["error"] == nil
            else {
                status = .disconnected
                return false
            }
            status = .connected
            return true
        } catch {
            status = .disconnected
            return false
        }
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

    private func secretParams(_ params: [Any]) -> [Any] {
        let token = SettingsStore.shared.secretToken.trimmingCharacters(in: .whitespaces)
        if token.isEmpty { return params }
        return ["token:\(token)"] + params
    }
}
