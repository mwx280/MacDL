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

    func addDownload(url: String, savePath: String? = nil, connections: Int? = nil) async -> String? {
        let filename = URL(string: url)?.lastPathComponent ?? "download"
        var options: [String: Any] = [
            "out": filename + ".download",
            "dir": config.stagingDirectory,
        ]
        if let connections { options["max-connection-per-server"] = "\(connections)" }
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
                if filename.hasSuffix(".download") { filename = String(filename.dropLast(9)) }
                if dir == nil { dir = URL(fileURLWithPath: path).deletingLastPathComponent().path }
            }
            if let uris = first["uris"] as? [[String: Any]], let firstUri = uris.first {
                extractedURL = firstUri["uri"] as? String ?? ""
            }
        }

        if filename == "unknown", let bt = dict["bittorrent"] as? [String: Any], let info = bt["info"] as? [String: Any] {
            filename = info["name"] as? String ?? "unknown"
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
            connections: connections
        )
    }
}
