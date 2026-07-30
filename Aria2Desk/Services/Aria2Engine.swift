import Foundation
import AppKit

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
final class Aria2Engine: EngineServiceProtocol {
    static let shared = Aria2Engine(portAllocator: PortAllocator.shared)
    let portAllocator: PortAllocatorProtocol

    var engineState: EngineState = .stopped
    var rpcPort = 0

    private var engineProcess: Process?
    private var terminationObserver: NSObjectProtocol?

    init(portAllocator: PortAllocatorProtocol) {
        self.portAllocator = portAllocator
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stop()
        }
    }

    deinit {
        stop()
    }

    private var enginePath: String {
        Bundle.main.bundlePath + "/Contents/MacOS/aria2c"
    }

    private var engineExists: Bool {
        FileManager.default.isExecutableFile(atPath: enginePath)
    }

    func start() {
        guard engineExists else {
            engineState = .error("Engine not found")
            return
        }
        if case .running = engineState { return }

        engineState = .starting
        rpcPort = portAllocator.findAvailablePort()
        ensureDirectories()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: enginePath)
        process.arguments = buildEngineArguments()
        process.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self, self.engineProcess === p else { return }
                self.engineProcess = nil
                self.engineState = p.terminationStatus == 0 ? .stopped : .error("Exit code \(p.terminationStatus)")
            }
        }

        do {
            try process.run()
            engineProcess = process
            engineState = .running
        } catch {
            engineState = .error(error.localizedDescription)
        }
    }

    func restart() {
        engineProcess?.terminate()
        engineProcess?.waitUntilExit()
        engineProcess = nil
        engineState = .stopped
        Thread.sleep(forTimeInterval: 0.3)
        start()
    }

    func stop() {
        guard let process = engineProcess else { return }
        process.terminationHandler = nil
        process.terminate()
        engineProcess = nil
        engineState = .stopped
        DispatchQueue.global().async {
            process.waitUntilExit()
        }
    }

    private func buildEngineArguments() -> [String] {
        let config = RPCConfig()
        var args = [
            "--enable-rpc",
            "--rpc-listen-all=true",
            "--rpc-allow-origin-all=true",
            "--rpc-listen-port=\(rpcPort)",
            "--max-connection-per-server=\(SettingsStore.shared.maxConnections)",
            "--max-concurrent-downloads=\(SettingsStore.shared.maxConcurrentDownloads)",
            "--dir=\(config.downloadDirectory)",
            "--input-file=\(config.aria2SessionPath)",
            "--save-session=\(config.aria2SessionPath)",
            "--save-session-interval=30",
            "--disable-ipv6=true",
        ]

        let token = SettingsStore.shared.secretToken.trimmingCharacters(in: .whitespaces)
        if !token.isEmpty {
            args.append("--rpc-secret=\(token)")
        }

        let dlSpeed = SettingsStore.shared.maxDownloadSpeed
        if dlSpeed > 0 {
            args.append("--max-download-limit=\(dlSpeed)")
        }
        let ulSpeed = SettingsStore.shared.maxUploadSpeed
        if ulSpeed > 0 {
            args.append("--max-upload-limit=\(ulSpeed)")
        }

        return args
    }

    private func ensureDirectories() {
        let config = RPCConfig()
        let fm = FileManager.default
        for dir in [config.appSupportDirectory, config.downloadDirectory] {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: config.aria2SessionPath) {
            fm.createFile(atPath: config.aria2SessionPath, contents: nil)
        }
    }
}
