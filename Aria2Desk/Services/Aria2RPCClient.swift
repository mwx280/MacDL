import Foundation
import Observation

@Observable
final class Aria2RPCClient {
    static let shared = Aria2RPCClient()

    var config = RPCConfig()
    var status: RPCConnectionStatus = .disconnected

    private init() {}

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

        guard let url = URL(string: config.baseURL),
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

    private func secretParams(_ params: [Any]) -> [Any] {
        let token = config.secretToken.trimmingCharacters(in: .whitespaces)
        if token.isEmpty { return params }
        return ["token:\(token)"] + params
    }
}
