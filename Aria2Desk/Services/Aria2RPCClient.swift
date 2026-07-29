import Foundation
import AppKit
import Observation
import Darwin

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
    var rpcPort = 0

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

    deinit {
        stopEngine()
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
        rpcPort = findAvailablePort()
        ensureDirectories()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: enginePath)
        process.arguments = buildEngineArguments()
        process.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self, self.engineProcess === p else { return }
                self.engineProcess = nil
                self.engineState = p.terminationStatus == 0 ? .stopped : .error("Exit code \(p.terminationStatus)")
                self.status = .disconnected
            }
        }

        do {
            try process.run()
            engineProcess = process
            engineState = .running
            autoConnect()
        } catch {
            engineState = .error(error.localizedDescription)
        }
    }

    func restartEngine() {
        stopEngine()
        Thread.sleep(forTimeInterval: 0.5)
        startEngine()
    }

    func stopEngine() {
        engineProcess?.terminationHandler = nil
        engineProcess?.terminate()
        engineProcess?.waitUntilExit()
        engineProcess = nil
        engineState = .stopped
        status = .disconnected
    }

    private func findAvailablePort() -> Int {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 6800 }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let len = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafePointer(to: &addr, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, len) == 0
            }
        }) else { return 6800 }

        var addrOut = sockaddr_in()
        var addrLen = len
        guard withUnsafeMutablePointer(to: &addrOut, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &addrLen) == 0
            }
        }) else { return 6800 }

        return Int(addrOut.sin_port.bigEndian)
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

    private func buildEngineArguments() -> [String] {
        var args = [
            "--enable-rpc",
            "--rpc-listen-all=true",
            "--rpc-allow-origin-all=true",
            "--rpc-listen-port=\(rpcPort)",
            "--max-connection-per-server=\(config.maxConnections)",
            "--max-concurrent-downloads=\(config.maxConcurrentDownloads)",
            "--dir=\(config.downloadDirectory)",
            "--input-file=\(config.aria2SessionPath)",
            "--save-session=\(config.aria2SessionPath)",
            "--save-session-interval=30",
            "--disable-ipv6=true",
        ]

        let token = config.secretToken.trimmingCharacters(in: .whitespaces)
        if !token.isEmpty {
            args.append("--rpc-secret=\(token)")
        }
        return args
    }

    private func ensureDirectories() {
        let fm = FileManager.default
        for dir in [config.appSupportDirectory, config.downloadDirectory] {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: config.aria2SessionPath) {
            fm.createFile(atPath: config.aria2SessionPath, contents: nil)
        }
    }

    private func autoConnect() {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            _ = await testConnection()
        }
    }

    private func secretParams(_ params: [Any]) -> [Any] {
        let token = config.secretToken.trimmingCharacters(in: .whitespaces)
        if token.isEmpty { return params }
        return ["token:\(token)"] + params
    }
}
