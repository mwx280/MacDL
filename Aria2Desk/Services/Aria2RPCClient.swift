import Foundation
import AppKit
import Observation

enum EngineState {
    case stopped
    case starting
    case running
    case error(String)

    var label: String {
        switch self {
        case .stopped: "Stopped"
        case .starting: "Starting..."
        case .running: "Running"
        case .error: "Error"
        }
    }
}

@Observable
final class Aria2RPCClient {
    static let shared = Aria2RPCClient()

    var config = RPCConfig()
    var status: RPCConnectionStatus = .disconnected
    var engineState: EngineState = .stopped

    private var engineProcess: Process?
    private var terminationObserver: NSObjectProtocol?

    private init() {
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopEngine()
        }
    }

    var enginePath: String {
        Bundle.main.bundlePath + "/Contents/MacOS/aria2c"
    }

    var engineExists: Bool {
        FileManager.default.isExecutableFile(atPath: enginePath)
    }

    func startEngine() {
        guard engineExists else {
            engineState = .error("Engine not found")
            return
        }
        if case .running = engineState { return }

        engineState = .starting
        let process = Process()
        process.executableURL = URL(fileURLWithPath: enginePath)

        var args = [
            "--enable-rpc",
            "--rpc-listen-all=true",
            "--rpc-allow-origin-all=true",
            "--rpc-listen-port=\(config.port)",
        ]
        let token = config.secretToken.trimmingCharacters(in: .whitespaces)
        if !token.isEmpty {
            args.append("--rpc-secret=\(token)")
        }
        process.arguments = args
        process.qualityOfService = .background

        do {
            try process.run()
            engineProcess = process
            engineState = .running
            monitorProcess(process)
        } catch {
            engineState = .error(error.localizedDescription)
        }
    }

    func stopEngine() {
        engineProcess?.terminate()
        engineProcess = nil
        engineState = .stopped
        status = .disconnected
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

    private func monitorProcess(_ process: Process) {
        DispatchQueue.global().async { [weak self] in
            process.waitUntilExit()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.engineProcess === process {
                    self.engineProcess = nil
                    if process.terminationStatus != 0 {
                        self.engineState = .error("Exit code \(process.terminationStatus)")
                    } else {
                        self.engineState = .stopped
                    }
                    self.status = .disconnected
                }
            }
        }
    }

    private func secretParams(_ params: [Any]) -> [Any] {
        let token = config.secretToken.trimmingCharacters(in: .whitespaces)
        if token.isEmpty { return params }
        return ["token:\(token)"] + params
    }
}
