import Foundation
import Observation

@Observable
final class Aria2RPCClient {
    static let shared = Aria2RPCClient(
        engine: Aria2Engine.shared,
        transport: RPCTransport.shared
    )

    let engine: EngineServiceProtocol
    let transport: RPCTransport

    var engineState: EngineState { engine.engineState }
    var status: RPCConnectionStatus { transport.status }
    var rpcPort: Int { engine.rpcPort }
    var config: RPCConfig { transport.config }
    var isConnected: Bool {
        guard transport.status == .connected else { return false }
        if case .running = engine.engineState { return true }
        return false
    }

    init(engine: EngineServiceProtocol, transport: RPCTransport) {
        self.engine = engine
        self.transport = transport
    }

    // MARK: - Engine Lifecycle

    func startEngine() {
        engine.start()
        if case .running = engine.engineState {
            transport.rpcPort = engine.rpcPort
            transport.autoConnect()
        }
    }

    func restartEngine() {
        engine.restart()
        if case .running = engine.engineState {
            transport.rpcPort = engine.rpcPort
            transport.autoConnect()
        }
    }

    func stopEngine() {
        engine.stop()
        transport.disconnect()
    }

    func testConnection() async -> Bool {
        await transport.testConnection()
    }

    func disconnect() {
        transport.disconnect()
    }

    // MARK: - Download Operations

    func addDownload(url: String, savePath: String? = nil, connections: Int? = nil, dlLimit: Int = 0, ulLimit: Int = 0) async -> String? {
        let filename = URL(string: url)?.lastPathComponent ?? "download"
        let dir = savePath ?? RPCConfig.defaultDownloadDir
        let packageDir = dir + "/" + filename + ".aria2desk"

        let fm = FileManager.default
        try? fm.createDirectory(atPath: packageDir, withIntermediateDirectories: true)
        try? (URL(fileURLWithPath: packageDir) as NSURL).setResourceValue(true, forKey: .isPackageKey)

        var options: [String: Any] = [
            "out": filename,
            "dir": packageDir,
        ]
        if let connections { options["max-connection-per-server"] = "\(connections)" }
        if dlLimit > 0 { options["max-download-limit"] = "\(dlLimit)" }
        if ulLimit > 0 { options["max-upload-limit"] = "\(ulLimit)" }
        for _ in 0..<5 {
            if let gid = await transport.addUri(uri: url, options: options) {
                return gid
            }
            try? await Task.sleep(for: .seconds(1))
        }
        return nil
    }

    func fetchAllDownloads() async -> [Download] {
        let active = await transport.tellActive()
        let waiting = await transport.tellWaiting()
        let stopped = await transport.tellStopped()
        return (active + waiting + stopped).compactMap { download(from: $0) }
    }

    func pauseDownload(gid: String) async {
        _ = await transport.pause(gid: gid)
    }

    func pauseAll() async {
        _ = await transport.pauseAll()
    }

    func resumeDownload(gid: String) async {
        _ = await transport.unpause(gid: gid)
    }

    func resumeAll() async {
        _ = await transport.unpauseAll()
    }

    func removeDownload(gid: String, status: DownloadStatus = .active) async {
        switch status {
        case .active, .waiting:
            _ = await transport.forceRemove(gid: gid)
            _ = await transport.removeDownloadResult(gid: gid)
        case .paused:
            _ = await transport.remove(gid: gid)
            _ = await transport.removeDownloadResult(gid: gid)
        case .completed, .stopped, .error:
            _ = await transport.removeDownloadResult(gid: gid)
        }
    }

    func changeConnections(gid: String, connections: Int) async {
        _ = await transport.changeOption(gid: gid, options: ["max-connection-per-server": "\(connections)"])
    }

    func setSpeedLimit(gid: String, key: String, value: String) async {
        _ = await transport.changeOption(gid: gid, options: [key: value])
    }

    func applySpeedLimits() async {
        var opts: [String: Any] = [:]
        opts["max-download-limit"] = "\(SettingsStore.shared.maxDownloadSpeed)"
        opts["max-upload-limit"] = "\(SettingsStore.shared.maxUploadSpeed)"
        _ = await transport.changeGlobalOption(opts)
    }

    // MARK: - Mapping

    private func download(from dict: [String: Any]) -> Download? {
        guard let gid = dict["gid"] as? String,
              let statusStr = dict["status"] as? String,
              let status = DownloadStatus(aria2Status: statusStr)
        else { return nil }

        let totalLength = Int64(dict["totalLength"] as? String ?? "") ?? 0
        let completedLength = Int64(dict["completedLength"] as? String ?? "") ?? 0
        let downloadSpeed = Int64(dict["downloadSpeed"] as? String ?? "") ?? 0
        let uploadSpeed = Int64(dict["uploadSpeed"] as? String ?? "") ?? 0
        let connections = (dict["connections"] as? String).flatMap(Int.init)

        var filename = "unknown"
        var dir = dict["dir"] as? String
        var extractedURL = ""

        if let files = dict["files"] as? [[String: Any]], let first = files.first {
            let path = first["path"] as? String ?? ""
            if !path.isEmpty {
                filename = URL(fileURLWithPath: path).lastPathComponent
                if dir == nil { dir = URL(fileURLWithPath: path).deletingLastPathComponent().path }
            }
            if let d = dir, d.hasSuffix(".aria2desk") {
                dir = URL(fileURLWithPath: d).deletingLastPathComponent().path
            }
            if let uris = first["uris"] as? [[String: Any]], let firstUri = uris.first {
                extractedURL = firstUri["uri"] as? String ?? ""
            }
        }

        if filename == "unknown", let bt = dict["bittorrent"] as? [String: Any], let info = bt["info"] as? [String: Any] {
            filename = info["name"] as? String ?? "unknown"
        }

        var errorMessage: String?
        if status == .error, let codeStr = dict["errorCode"] as? String, let code = Int(codeStr) {
            let msg = dict["errorMessage"] as? String
            errorMessage = Self.errorDescription(code: code, message: msg)
        }

        return Download(
            gid: gid,
            filename: filename,
            url: extractedURL,
            totalSize: totalLength,
            downloadedSize: completedLength,
            downloadSpeed: downloadSpeed,
            uploadSpeed: uploadSpeed,
            status: status,
            savePath: dir,
            connections: connections,
            errorMessage: errorMessage
        )
    }

    private static func errorDescription(code: Int, message: String?) -> String {
        let loc = LanguageManager.shared.localized
        switch code {
        case 0: return loc("Completed")
        case 1: return loc("Unknown error")
        case 2: return loc("Timeout")
        case 3: return loc("Not Found")
        case 4: return loc("Resume not supported")
        case 5: return loc("Connection refused")
        case 6: return loc("Connection failed")
        case 7: return loc("DNS failed")
        case 8: return loc("Checksum error")
        case 9: return loc("Peer not found")
        case 10: return loc("Already downloaded")
        case 11: return loc("Cancelled")
        case 12: return loc("Cannot create folder")
        case 13: return loc("Cannot write file")
        case 14: return loc("Too slow")
        case 15: return loc("SSL/TLS error")
        case 16: return loc("Invalid metalink")
        case 17: return loc("Command error")
        case 18: return loc("Disk full")
        case 19: return loc("Duplicate task")
        case 20: return loc("URL too long")
        case 21: return loc("File not found")
        case 22: return loc("Server error")
        case 23: return loc("IP blocked")
        case 24: return loc("Proxy error")
        case 25: return loc("GeoIP blocked")
        default:
            if let msg = message, !msg.isEmpty { return loc("Unknown error") }
            return "\(loc("Error")) (\(code))"
        }
    }
}
